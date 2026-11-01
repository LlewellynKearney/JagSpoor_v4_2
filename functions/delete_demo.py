import firebase_admin
from firebase_admin import credentials, firestore
import os

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = r'C:\Users\llewe\Documents\keys\jagspoor-service-account.json'
if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.client()
uid = 'ieqqYhHRYngRaepIoPfkCJnmAyf1'
email = 'demo@jag-spoor.co.za'

collections = ['packages', 'hunting_packages', 'outfitters', 'bookings']

for col in collections:
    print(f'Checking {col}...')
    try:
        docs = list(db.collection(col).where('uid', '==', uid).stream())
        docs += list(db.collection(col).where('createdBy', '==', uid).stream())
        docs += list(db.collection(col).where('ownerId', '==', uid).stream())
        docs += list(db.collection(col).where('email', '==', email).stream())
        # Deduplicate
        seen = set()
        to_del = []
        for d in docs:
            if d.id not in seen:
                seen.add(d.id)
                to_del.append(d)
        print(f'  Found {len(to_del)} in {col}')
        for d in to_del:
            print(f'    Deleting {col}/{d.id}')
            d.reference.delete()
    except Exception as e:
        print(f'  Error in {col}: {e}')

# Disable user doc
try:
    db.collection('users').document(uid).set({'disabled': True, 'role': 'disabled', 'updatedAt': firestore.SERVER_TIMESTAMP}, merge=True)
    print(f'Disabled user {uid}')
except Exception as e:
    print(e)

print('Done')
