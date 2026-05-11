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
      let uid, action, secret, amount;

      const contentType = request.headers.get("Content-Type") || "";

      // SOPORTE UNIVERSAL: Lee de URL (GET) o de JSON (POST)
      if (request.method === "POST" && contentType.includes("application/json")) {
        const body = await request.json();
        uid = body.uid;
        action = body.action;
        secret = body.secret;
        amount = parseInt(body.amount || "1");
      } else {
        // Para imágenes o peticiones con params en URL
        uid = url.searchParams.get("uid");
        action = url.searchParams.get("action");
        secret = url.searchParams.get("secret") || request.headers.get("Authorization");
        amount = parseInt(url.searchParams.get("amount") || "1");
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
        currentCredits += amount;
      } else if (action === 'use') {
        if (currentCredits < amount) return new Response('No credits', { status: 400 });
        currentCredits -= amount;
      } else if (action === 'refine_signature') {
        if (currentCredits < amount) return new Response('Insufficient credits', { status: 403 });
        
        // 1. Obtener imagen de la petición
        const imageData = await request.arrayBuffer();
        
        // 2. Procesar con IA (Detección/Entendimiento)
        await env.AI.run('@cf/microsoft/resnet-50', {
          image: [...new Uint8Array(imageData)]
        });

        currentCredits -= amount;

        // 3. Actualizar Firestore antes de devolver la imagen
        await fetch(`${firestoreUrl}?updateMask.fieldPaths=credits`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            fields: { credits: { integerValue: currentCredits.toString() } }
          })
        });

        // --- REGISTRO EN D1 (HISTORIAL) ---
        try {
          await env.DB.prepare(
            "INSERT INTO movements (uid, action, amount, description) VALUES (?, ?, ?, ?)"
          ).bind(uid, action, -amount, "Refinamiento de firma con IA").run();
        } catch (dbError) {
          console.error(`[D1 Error] ${dbError.message}`);
        }

        // 4. Retornar la imagen procesada
        return new Response(imageData, {
          headers: { 
            "Content-Type": "image/png",
            "X-Credits-Left": currentCredits.toString(),
            "Access-Control-Allow-Origin": "*" 
          }
        });
      } else if (action === 'history') {
        const { results } = await env.DB.prepare(
          "SELECT * FROM movements WHERE uid = ? ORDER BY timestamp DESC LIMIT 50"
        ).bind(uid).all();
        
        return new Response(JSON.stringify({ success: true, history: results }), {
          status: 200,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      } else if (action === 'log') {
        const customDesc = url.searchParams.get("desc") || "Evento registrado";
        const logAmount = parseInt(url.searchParams.get("amount") || "0");
        try {
          await env.DB.prepare(
            "INSERT INTO movements (uid, action, amount, description) VALUES (?, ?, ?, ?)"
          ).bind(uid, 'add', logAmount, customDesc).run();
        } catch (dbError) {
          console.error(`[D1 Error] ${dbError.message}`);
        }
        return new Response(JSON.stringify({ success: true }), { 
          status: 200, 
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      } else if (action === 'referral') {
        const referrerUid = url.searchParams.get("ref");
        if (!referrerUid) return new Response('Missing referrer', { status: 400 });

        // 1. Dar 5 al nuevo usuario
        currentCredits += 5;

        // 2. Dar 5 al referente en Firestore (Petición externa)
        const referrerUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${referrerUid}`;
        const refGet = await fetch(referrerUrl);
        if (refGet.status === 200) {
          const refDoc = await refGet.json();
          const refOldCredits = parseInt(refDoc.fields?.credits?.integerValue || "0");
          const refNewCredits = refOldCredits + 5;

          await fetch(`${referrerUrl}?updateMask.fieldPaths=credits`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fields: { credits: { integerValue: refNewCredits.toString() } } })
          });

          // Log para el referente
          await env.DB.prepare(
            "INSERT INTO movements (uid, action, amount, description) VALUES (?, ?, ?, ?)"
          ).bind(referrerUid, 'add', 5, `Bono por invitar a usuario ${uid}`).run();
        }

        // Log para el nuevo usuario
        await env.DB.prepare(
          "INSERT INTO movements (uid, action, amount, description) VALUES (?, ?, ?, ?)"
        ).bind(uid, 'add', 5, "Regalo por invitación").run();

      } else {
        return new Response('Invalid action', { status: 400 });
      }

      // 3. Guardar en Firestore (Si es add o use o si se envió app_version)
      const appVersion = url.searchParams.get("app_version");

      if (action === 'add' || action === 'use' || (action === 'get' && appVersion)) {
        console.log(`[Worker] Actualizando Firestore...`);
        const fieldsToUpdate = {};
        if (action === 'add' || action === 'use') fieldsToUpdate.credits = { integerValue: currentCredits.toString() };
        if (appVersion) fieldsToUpdate.app_version = { stringValue: appVersion };

        const queryParams = new URLSearchParams();
        Object.keys(fieldsToUpdate).forEach(key => queryParams.append('updateMask.fieldPaths', key));

        const patchResponse = await fetch(`${firestoreUrl}?${queryParams.toString()}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ fields: fieldsToUpdate })
        });

        if (!patchResponse.ok) {
          const errorText = await patchResponse.text();
          console.error(`[Firebase] Error Update: ${errorText}`);
          return new Response(`Error: ${errorText}`, { status: patchResponse.status });
        }

        // --- REGISTRO EN D1 (HISTORIAL) ---
        if (action === 'add' || action === 'use') {
          try {
            const customDesc = url.searchParams.get("desc");
            const defaultDesc = action === 'add' ? "Crédito añadido" : "Uso de servicio";
            const finalDesc = customDesc || defaultDesc;

            await env.DB.prepare(
              "INSERT INTO movements (uid, action, amount, description) VALUES (?, ?, ?, ?)"
            ).bind(uid, action, (action === 'use' ? -amount : amount), finalDesc).run();
          } catch (dbError) {
            console.error(`[D1 Error] ${dbError.message}`);
          }
        }
      }

      // Obtener force_update_to de Firestore para la respuesta
      let forceUpdateTo = "";
      const finalGet = await fetch(firestoreUrl);
      if (finalGet.status === 200) {
        const doc = await finalGet.json();
        forceUpdateTo = doc.fields?.force_update_to?.stringValue || "";
      }

      return new Response(JSON.stringify({ 
        success: true, 
        credits: currentCredits,
        force_update_to: forceUpdateTo 
      }), {
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
