const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.deductCredit = functions.https.onCall(async (data, context) => {
  // Verificación de autenticación
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated", 
      "El usuario debe estar autenticado."
    );
  }

  const uid = context.auth.uid;
  const userRef = admin.firestore().collection("users").doc(uid);

  return admin.firestore().runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);

    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Usuario no encontrado.");
    }

    const currentCredits = userDoc.data().credits || 0;

    if (currentCredits <= 0) {
      throw new functions.https.HttpsError(
        "failed-precondition", 
        "Créditos insuficientes."
      );
    }

    transaction.update(userRef, { credits: currentCredits - 1 });
    return { success: true, remainingCredits: currentCredits - 1 };
  });
});
