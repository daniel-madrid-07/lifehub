import requests

API = "https://api.telegram.org/bot{token}/{method}"


def send_message(env, text):
    token = env.get("TELEGRAM_BOT_TOKEN")
    chat_id = env.get("TELEGRAM_CHAT_ID")
    if not token or not chat_id:
        return
    requests.post(
        API.format(token=token, method="sendMessage"),
        data={
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        },
        timeout=30,
    )
