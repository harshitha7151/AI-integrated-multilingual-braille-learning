"""Seed script for demo/pilot presentations.
Creates 1 demo teacher and 6 learners with varied progress:
- 2 active (good accuracy, recent practice)
- 2 inactive (practiced >7 days ago)
- 2 struggling (low accuracy, mistakes on specific letters)

Refuses to run when ENV=production.
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from uuid import uuid4

# Refuse to run in production
current_env = os.getenv("ENV", "development").strip().lower()
if current_env == "production":
    print("ERROR: seed_demo_data.py refuses to run when ENV=production.")
    sys.exit(1)

# Ensure JWT secret is set for teacher password hashing/token support
if not os.getenv("RESONANT_JWT_SECRET"):
    os.environ["RESONANT_JWT_SECRET"] = "demo-seed-secret-key-32-chars-long!!"

from database import get_connection
from teacher_service import signup_teacher


def seed_demo_data():
    print(f"Running demo seed in {current_env} environment...")

    with get_connection() as conn:
        # Check if demo teacher already exists
        demo_email = "demo.teacher@example.com"
        row = conn.execute(
            "SELECT teacher_id FROM resonant.teachers WHERE email = lower(%s)",
            (demo_email,),
        ).fetchone()

        if row:
            teacher_id = str(row["teacher_id"])
            print(f"Demo teacher already exists with ID: {teacher_id}")
        else:
            created = signup_teacher(
                name="Ananya Sharma",
                email=demo_email,
                password="password123",
                organization="St. Agnes Academy for the Blind",
            )
            teacher_id = str(created["teacher_id"])
            print(f"Created demo teacher: {demo_email} (password: password123)")

        # Define 6 learners with distinct profiles
        learners_spec = [
            # Active learners (high accuracy, recent attempts)
            {
                "name": "Aarav Patel",
                "phone": "9876543201",
                "batch": "Morning Batch A",
                "days_ago": 1,
                "total_attempts": 24,
                "correct_ratio": 0.92,
                "weak_skills": ["english-letter-q"],
            },
            {
                "name": "Diya Sundaram",
                "phone": "9876543202",
                "batch": "Morning Batch A",
                "days_ago": 0,
                "total_attempts": 30,
                "correct_ratio": 0.88,
                "weak_skills": ["english-letter-z"],
            },
            # Inactive learners (practiced > 7 days ago)
            {
                "name": "Rahul Verma",
                "phone": "9876543203",
                "batch": "Afternoon Batch B",
                "days_ago": 12,
                "total_attempts": 15,
                "correct_ratio": 0.80,
                "weak_skills": ["english-letter-j", "english-letter-k"],
            },
            {
                "name": "Meera Joshi",
                "phone": "9876543204",
                "batch": "Afternoon Batch B",
                "days_ago": 14,
                "total_attempts": 10,
                "correct_ratio": 0.70,
                "weak_skills": ["english-letter-m"],
            },
            # Struggling learners (low accuracy, high error count)
            {
                "name": "Kabir Khan",
                "phone": "9876543205",
                "batch": "Morning Batch A",
                "days_ago": 2,
                "total_attempts": 28,
                "correct_ratio": 0.42,
                "weak_skills": ["english-letter-d", "english-letter-f", "english-letter-h"],
            },
            {
                "name": "Sneha Roy",
                "phone": "9876543206",
                "batch": "Evening Special",
                "days_ago": 1,
                "total_attempts": 22,
                "correct_ratio": 0.50,
                "weak_skills": ["english-letter-b", "english-letter-p", "english-letter-r"],
            },
        ]

        now = datetime.now(timezone.utc)

        for spec in learners_spec:
            # Check or create learner
            existing_learner = conn.execute(
                "SELECT learner_id FROM resonant.learners WHERE phone = %s",
                (spec["phone"],),
            ).fetchone()

            if existing_learner:
                lid = existing_learner["learner_id"]
                # Update teacher assignment
                conn.execute(
                    "UPDATE resonant.learners SET teacher_id = %s, batch = %s WHERE learner_id = %s",
                    (teacher_id, spec["batch"], lid),
                )
                print(f"Updated existing learner: {spec['name']}")
            else:
                lid = uuid4()
                conn.execute(
                    """
                    INSERT INTO resonant.learners
                        (learner_id, username, preferred_language, name, phone, batch, consent_at, teacher_id)
                    VALUES (%s, %s, 'English', %s, %s, %s, now(), %s)
                    """,
                    (lid, spec["name"], spec["name"], spec["phone"], spec["batch"], teacher_id),
                )
                print(f"Created learner: {spec['name']}")

            # Seed practice attempts & skill progress
            last_date = now - timedelta(days=spec["days_ago"])
            total = spec["total_attempts"]
            correct_count = int(total * spec["correct_ratio"])
            incorrect_count = total - correct_count

            # Delete old mock attempts if re-running
            conn.execute("DELETE FROM resonant.practice_attempts WHERE learner_id = %s", (lid,))
            conn.execute("DELETE FROM resonant.skill_progress WHERE learner_id = %s", (lid,))

            for i in range(total):
                is_correct = i < correct_count
                attempt_time = last_date - timedelta(hours=i * 2)
                skill = spec["weak_skills"][0] if (not is_correct and spec["weak_skills"]) else "english-letter-a"
                conn.execute(
                    """
                    INSERT INTO resonant.practice_attempts
                        (submission_id, learner_id, exercise_id, skill_id, language,
                         exercise_type, outcome, response_time_ms, hint_used, attempt_number, created_at)
                    VALUES (%s, %s, %s, %s, 'English', 'letter_recognition', %s, %s, %s, %s, %s)
                    """,
                    (
                        uuid4(),
                        lid,
                        f"exercise-{skill}",
                        skill,
                        "correct" if is_correct else "incorrect",
                        1200 + (i * 50),
                        not is_correct,
                        1,
                        attempt_time,
                    ),
                )

            # Insert skill progress summary
            for w in spec["weak_skills"]:
                conn.execute(
                    """
                    INSERT INTO resonant.skill_progress
                        (learner_id, skill_id, language, attempts, correct_count, mastery, average_response_ms, updated_at)
                    VALUES (%s, %s, 'English', 8, 2, 0.25, 1800, %s)
                    ON CONFLICT (learner_id, skill_id) DO NOTHING
                    """,
                    (lid, w, last_date),
                )

    print("Demo seed completed successfully!")


if __name__ == "__main__":
    seed_demo_data()

