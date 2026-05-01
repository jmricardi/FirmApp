export default {
  async fetch(request, env) {
    // Manejo de CORS
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    try {
      const url = new URL(request.url);
      let uid, action, secret;

      // SOPORTE UNIVERSAL: Lee de URL (GET) o de JSON (POST)
      if (request.method === "POST") {
        const body = await request.json();
        uid = body.uid;
        action = body.action;
        secret = body.secret;
      } else {
        uid = url.searchParams.get("uid");
        action = url.searchParams.get("action");
        // Soporta secreto en URL o en header Authorization
        secret = url.searchParams.get("secret") || request.headers.get("Authorization");
      }

      console.log(`[Worker] Petición recibida - Acción: ${action}, UID: ${uid}`);

      // Validación de seguridad (Usamos el nombre exacto WORker_SECRET)
      if (secret !== env.WORker_SECRET) {
        console.error("[Worker] Error: Secreto inválido.");
        return new Response('Unauthorized', { status: 401 });
      }

      if (!uid || !action) {
        return new Response('Missing parameters', { status: 400 });
      }

      const projectId = env.FIREBASE_PROJECT_ID;
      const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}`;

      // 1. Obtener los créditos actuales
      console.log("[Worker] Consultando Firestore...");
      const getResponse = await fetch(firestoreUrl);
      let currentCredits = 0;
      
      if (getResponse.status === 200) {
        const doc = await getResponse.json();
        currentCredits = parseInt(doc.fields?.credits?.integerValue || "0");
      } else if (getResponse.status !== 404) {
        const errorText = await getResponse.text();
        console.error(`[Firebase] Error Read (Status ${getResponse.status}): ${errorText}`);
        return new Response(`Error: ${errorText}`, { status: getResponse.status });
      }

      // 2. Lógica de negocio
      if (action === 'get') {
        // Solo devolver créditos actuales
      } else if (action === 'add') {
        currentCredits += 1;
      } else if (action === 'use') {
        if (currentCredits <= 0) return new Response('No credits', { status: 400 });
        currentCredits -= 1;
      } else {
        return new Response('Invalid action', { status: 400 });
      }

      // 3. Guardar en Firestore (Si es add o use)
      if (action === 'add' || action === 'use') {
        console.log(`[Worker] Actualizando créditos a: ${currentCredits}`);
        const patchResponse = await fetch(`${firestoreUrl}?updateMask.fieldPaths=credits`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            fields: {
              credits: { integerValue: currentCredits.toString() }
            }
          })
        });

        if (!patchResponse.ok) {
          const errorText = await patchResponse.text();
          console.error(`[Firebase] Error Update: ${errorText}`);
          return new Response(`Error: ${errorText}`, { status: patchResponse.status });
        }
      }

      return new Response(JSON.stringify({ success: true, credits: currentCredits }), {
        status: 200,
        headers: { 
          "Content-Type": "application/json", 
          "Access-Control-Allow-Origin": "*" 
        }
      });

    } catch (e) {
      console.error(`[Worker] Error Crítico: ${e.message}`);
      return new Response(JSON.stringify({ error: e.message }), { 
        status: 500,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }
  }
};
