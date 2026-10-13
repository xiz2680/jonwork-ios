#!/usr/bin/env python3

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LANGUAGES = ("de", "en", "es", "fr", "ja", "ko", "zh-Hans")
COPYRIGHT = "Copyright © 2026 Jonwork. All rights reserved."


def entry(comment: str, values: dict[str, str], should_translate: bool = True) -> dict:
    result = {
        "comment": comment,
        "localizations": {
            language: {"stringUnit": {"state": "translated", "value": values[language]}}
            for language in LANGUAGES
        },
    }
    if not should_translate:
        result["shouldTranslate"] = False
    return result


def repeated(value: str) -> dict[str, str]:
    return {language: value for language in LANGUAGES}


def write_catalog(path: Path, strings: dict) -> None:
    path.write_text(
        json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, ensure_ascii=False, indent=2)
        + "\n",
        encoding="utf-8",
    )
    print(f"[+] updated {path.relative_to(ROOT)}")


main_strings = {
    "CFBundleDisplayName": entry("Bundle display name", repeated("Jonwork"), False),
    "CFBundleName": entry("Bundle name", repeated("Jonwork"), False),
    "NSCameraUsageDescription": entry("Privacy - Camera Usage Description", {
        "de": "Jonwork verwendet die Kamera nur, wenn du ein neues Foto an eine Unterhaltung anhängst.",
        "en": "Jonwork uses the camera only when you choose to attach a new photo to a conversation.",
        "es": "Jonwork usa la cámara solo cuando decides adjuntar una foto nueva a una conversación.",
        "fr": "Jonwork utilise l’appareil photo uniquement lorsque vous choisissez de joindre une nouvelle photo à une conversation.",
        "ja": "Jonworkは、会話に新しい写真を添付することを選択した場合にのみカメラを使用します。",
        "ko": "Jonwork는 대화에 새 사진을 첨부하도록 선택한 경우에만 카메라를 사용합니다.",
        "zh-Hans": "Jonwork 仅在您选择为对话拍摄并附加新照片时使用相机。",
    }),
    "NSHumanReadableCopyright": entry("Copyright (human-readable)", repeated(COPYRIGHT), False),
    "NSLocalNetworkUsageDescription": entry("Privacy - Local Network Usage Description", {
        "de": "Jonwork verwendet dein lokales Netzwerk nur, wenn eine Verbindung zu einem Workspace in deinem Netzwerk hergestellt wird.",
        "en": "Jonwork uses your local network only when connecting to a workspace on your network.",
        "es": "Jonwork usa tu red local solo cuando se conecta a un espacio de trabajo de tu red.",
        "fr": "Jonwork utilise votre réseau local uniquement pour se connecter à un espace de travail présent sur ce réseau.",
        "ja": "Jonworkは、ローカルネットワーク上のワークスペースに接続する場合にのみローカルネットワークを使用します。",
        "ko": "Jonwork는 로컬 네트워크의 워크스페이스에 연결할 때만 로컬 네트워크를 사용합니다.",
        "zh-Hans": "Jonwork 仅在连接您本地网络中的工作区时使用本地网络。",
    }),
    "NSMicrophoneUsageDescription": entry("Privacy - Microphone Usage Description", {
        "de": "Jonwork verwendet das Mikrofon nur, wenn du eine Nachricht diktierst. Audio wird von Apples Spracherkennungsdienst verarbeitet.",
        "en": "Jonwork uses the microphone only when you choose to dictate a message. Audio is processed by Apple's speech recognition service.",
        "es": "Jonwork usa el micrófono solo cuando decides dictar un mensaje. El audio se procesa mediante el servicio de reconocimiento de voz de Apple.",
        "fr": "Jonwork utilise le microphone uniquement lorsque vous choisissez de dicter un message. L’audio est traité par le service de reconnaissance vocale d’Apple.",
        "ja": "Jonworkは、メッセージの音声入力を選択した場合にのみマイクを使用します。音声はAppleの音声認識サービスで処理されます。",
        "ko": "Jonwork는 메시지 받아쓰기를 선택한 경우에만 마이크를 사용합니다. 오디오는 Apple의 음성 인식 서비스에서 처리됩니다.",
        "zh-Hans": "Jonwork 仅在您选择听写消息时使用麦克风。音频由 Apple 的语音识别服务处理。",
    }),
    "NSPhotoLibraryAddUsageDescription": entry("Privacy - Photo Library Additions Usage Description", {
        "de": "Jonwork greift nur dann auf deine Fotomediathek zu, wenn du ein Bild speicherst.",
        "en": "Jonwork uses photo library access only when you choose to save an image.",
        "es": "Jonwork accede a tu fototeca solo cuando decides guardar una imagen.",
        "fr": "Jonwork accède à votre photothèque uniquement lorsque vous choisissez d’enregistrer une image.",
        "ja": "Jonworkは、画像の保存を選択した場合にのみ写真ライブラリへのアクセスを使用します。",
        "ko": "Jonwork는 이미지를 저장하도록 선택한 경우에만 사진 보관함에 접근합니다.",
        "zh-Hans": "Jonwork 仅在您选择保存图片时访问照片图库。",
    }),
    "NSSpeechRecognitionUsageDescription": entry("Privacy - Speech Recognition Usage Description", {
        "de": "Jonwork verwendet Apples Spracherkennungsdienst nur, wenn du eine Nachricht diktierst.",
        "en": "Jonwork uses Apple's speech recognition service only when you choose to dictate a message.",
        "es": "Jonwork usa el servicio de reconocimiento de voz de Apple solo cuando decides dictar un mensaje.",
        "fr": "Jonwork utilise le service de reconnaissance vocale d’Apple uniquement lorsque vous choisissez de dicter un message.",
        "ja": "Jonworkは、メッセージの音声入力を選択した場合にのみAppleの音声認識サービスを使用します。",
        "ko": "Jonwork는 메시지 받아쓰기를 선택한 경우에만 Apple의 음성 인식 서비스를 사용합니다.",
        "zh-Hans": "Jonwork 仅在您选择听写消息时使用 Apple 的语音识别服务。",
    }),
}

translation_strings = {
    "CFBundleDisplayName": entry("Bundle display name", repeated("Jonwork Translate"), False),
    "CFBundleName": entry("Bundle name", repeated("JonworkTranslationProvider"), False),
    "NSHumanReadableCopyright": entry("Copyright (human-readable)", repeated(COPYRIGHT), False),
}

widget_strings = {
    "CFBundleDisplayName": entry("Bundle display name", repeated("Jonwork Widgets"), False),
    "CFBundleName": entry("Bundle name", repeated("JonworkWidgets"), False),
    "NSHumanReadableCopyright": entry("Copyright (human-readable)", repeated(COPYRIGHT), False),
}

write_catalog(ROOT / "Jonwork/Resources/InfoPlist.xcstrings", main_strings)
write_catalog(ROOT / "JonworkTranslationProvider/InfoPlist.xcstrings", translation_strings)
write_catalog(ROOT / "JonworkWidgets/InfoPlist.xcstrings", widget_strings)
