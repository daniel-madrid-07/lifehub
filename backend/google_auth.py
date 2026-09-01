"""Genera token.json para Gmail + Google Calendar (correr en local, una vez).

Uso:
    cd backend
    python google_auth.py

Abre el navegador para autorizar la cuenta de Google. Tras aceptar, guarda
backend/token.json con el refresh_token. app/google_client.py usa ese
archivo (y lo refresca solo) para llamar a las APIs de Gmail/Calendar.
"""
from google_auth_oauthlib.flow import InstalledAppFlow

from app.config import load_env

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
]


def main():
    env = load_env()
    client_config = {
        "installed": {
            "client_id": env["GOOGLE_CLIENT_ID"],
            "client_secret": env["GOOGLE_CLIENT_SECRET"],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }
    flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
    creds = flow.run_local_server(port=0)

    with open("token.json", "w", encoding="utf-8") as f:
        f.write(creds.to_json())

    # registra la fecha de autorizacion para el contador de caducidad (7 dias)
    try:
        from app.auth import set_authorized_now
        set_authorized_now()
    except Exception:
        pass

    print("token.json generado correctamente.")


if __name__ == "__main__":
    main()
