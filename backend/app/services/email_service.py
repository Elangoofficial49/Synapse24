import httpx

from app.core.config import settings


async def send_registration_otp_email(email: str, code: str) -> None:
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={
                "accept": "application/json",
                "api-key": settings.BREVO_API_KEY,
                "content-type": "application/json",
            },
            json={
                "sender": {
                    "name": settings.BREVO_SENDER_NAME,
                    "email": settings.BREVO_SENDER_EMAIL,
                },
                "to": [{"email": email}],
                "subject": "Your PharmaTrace registration verification code",
                "textContent": (
                    f"Your PharmaTrace verification code is {code}. "
                    "It expires in 10 minutes."
                ),
                "htmlContent": (
                    "<p>Your PharmaTrace verification code is "
                    f"<strong>{code}</strong>.</p>"
                    "<p>It expires in 10 minutes. If you did not request "
                    "this code, you can ignore this email.</p>"
                ),
            },
        )
        response.raise_for_status()
