export default {
  async fetch(request, env) {
    // Manejo de CORS para peticiones desde la App
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    try {
      const body = await request.json();
      const { uid, action, secret } = body;

      console.log(`[Worker] Petición recibida - Acción: ${action}, UID: ${uid}`);

      // Validación de seguridad
      if (secret !== env.WORker_SECRET) {
        console.error("[Worker] Error: El secreto enviado no coincide con el configurado.");
        return new Response('Unauthorized', { status: 401 });
      }

      const projectId = env.FIREBASE_PROJECT_ID;
      const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}`;

      // 1. Obtener los créditos actuales
      console.log("[Worker] Consultando créditos en Firestore...");
      const getResponse = await fetch(firestoreUrl);
      let currentCredits = 0;
      
      if (getResponse.status === 200) {
        const doc = await getResponse.json();
        currentCredits = parseInt(doc.fields?.credits?.integerValue || "0");
        console.log(`[Worker] Créditos encontrados: ${currentCredits}`);
      } else if (getResponse.status === 404) {
        console.log("[Worker] El documento del usuario no existe. Se asumen 0 créditos.");
      } else {
        const errorText = await getResponse.text();
        console.error(`[Firebase] Error al consultar (Status ${getResponse.status}): ${errorText}`);
        return new Response(`Firebase Read Error: ${errorText}`, { status: getResponse.status });
      }

      // 2. Aplicar la lógica de negocio
      if (action === 'deduct') {
        if (currentCredits <= 0) {
          console.warn("[Worker] Intento de descuento fallido: Usuario no tiene créditos.");
          return new Response(JSON.stringify({ error: 'No hay créditos disponibles' }), { 
            status: 400,
            headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
          });
        }
        currentCredits -= 1;
      } else if (action === 'add') {
        currentCredits += 1;
      } else {
        return new Response('Acción no válida', { status: 400 });
      }

      // 3. Guardar el nuevo valor en Firestore
      console.log(`[Worker] Guardando nuevo valor: ${currentCredits} créditos...`);
      const patchResponse = await fetch(`${firestoreUrl}?updateMask.fieldPaths=credits`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fields: {
            credits: { integerValue: currentCredits.toString() }
          }
        })
      });

      if (patchResponse.ok) {
        console.log("[Worker] Éxito: Firestore actualizado correctamente.");
        return new Response(JSON.stringify({ success: true, credits: currentCredits }), {
          status: 200,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      } else {
        const patchError = await patchResponse.text();
        console.error(`[Firebase] Error al actualizar (Status ${patchResponse.status}): ${patchError}`);
        return new Response(`Firebase Update Error: ${patchError}`, { status: patchResponse.status });
      }

    } catch (e) {
      console.error(`[Worker] Error Crítico Interno: ${e.message}`);
      return new Response(JSON.stringify({ error: e.message }), { 
        status: 500,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }
  }
};
