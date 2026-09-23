const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

const SENSITIVE_FIELDS = [
  'idNumber',
  'bloodType',
  'allergies',
  'medicalAid',
  'medicalAidNumber',
  'emergencyContact',
  'hunterStatus',
  'provincialPermits'
];

async function migrate() {
  console.log('Starting scrub...');
  const usersSnap = await db.collection('users').get();
  let migrated = 0;
  let alreadyClean = 0;

  for (const userDoc of usersSnap.docs) {
    const data = userDoc.data();
    const hasSensitive = SENSITIVE_FIELDS.some(f => data.hasOwnProperty(f));

    if (!hasSensitive) {
      alreadyClean++;
      continue;
    }

    console.log(`Migrating ${userDoc.id} - found: ${SENSITIVE_FIELDS.filter(f => data.hasOwnProperty(f)).join(', ')}`);

    const privateData = {};
    const deletes = {};

    SENSITIVE_FIELDS.forEach(f => {
      if (data.hasOwnProperty(f)) {
        privateData[f] = data[f];
        deletes[f] = FieldValue.delete();
      }
    });

    await db.collection('users').doc(userDoc.id)
    .collection('private').doc('profile')
    .set(privateData, { merge: true });

    await db.collection('users').doc(userDoc.id).update(deletes);

    migrated++;
  }

  console.log(`\nDone. Migrated: ${migrated}, Already clean: ${alreadyClean}, Total: ${usersSnap.size}`);
}

migrate().catch(console.error);
