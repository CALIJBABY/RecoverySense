"""
Count Firestore sessions and sensor batches by participant.

This utility supports dataset selection and does not download participant
sensor samples or run a machine-learning model.
"""
from recoverysense_ml.firestore_export import initialize_firebase

db = initialize_firebase()

print("\nRecoverySense participant data counts\n")

for participant in db.collection("participants").stream():
    batch_count = 0
    session_count = 0

    for session in participant.reference.collection("sessions").stream():
        session_count += 1
        result = session.reference.collection("sensor_batches").count().get()
        batch_count += int(result[0][0].value)

    print(
        f"{participant.id} | "
        f"sessions: {session_count} | "
        f"sensor batches: {batch_count}"
    )

