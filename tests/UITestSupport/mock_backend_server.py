#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import re
import sys
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class MockState:
    def __init__(self, image_path: Path) -> None:
        self.image_bytes = image_path.read_bytes()
        self.image_filename = image_path.name
        self.base64_length = len(base64.b64encode(self.image_bytes).decode("ascii"))
        self.next_id = 2
        self.records = [
            self._make_record(
                record_id=1,
                image_name="Existing Library Image",
                description="Existing reusable description for the image.",
                created_at=datetime(2026, 3, 23, 12, 0, 0),
            )
        ]

    def _make_record(
        self,
        record_id: int,
        image_name: str,
        description: str,
        created_at: datetime,
    ) -> dict:
        timestamp = created_at.isoformat()
        return {
            "id": record_id,
            "imageName": image_name,
            "originalFilename": self.image_filename,
            "mimeType": "image/png",
            "description": description,
            "base64Length": self.base64_length,
            "createdAt": timestamp,
            "updatedAt": timestamp,
        }

    def list_records(self, search: str) -> list[dict]:
        filtered = self.records
        if search.strip():
            lowered = search.lower()
            filtered = [record for record in self.records if lowered in record["imageName"].lower()]
        return sorted(filtered, key=lambda record: (record["createdAt"], record["id"]), reverse=True)

    def create_uploaded_record(self, image_name: str, description: str) -> dict:
        record = self._make_record(
            record_id=self.next_id,
            image_name=image_name,
            description=description,
            created_at=datetime(2026, 3, 23, 12, 5, 0) + timedelta(seconds=self.next_id),
        )
        self.records.append(record)
        self.next_id += 1
        return record

    def update_description(self, record_id: int, description: str) -> dict | None:
        record = self.get_record(record_id)
        if not record:
            return None
        record["description"] = description
        updated_at = datetime.fromisoformat(record["updatedAt"]) + timedelta(minutes=1)
        record["updatedAt"] = updated_at.isoformat()
        return record

    def generate_description(self, record_id: int, prompt: str) -> dict | None:
        record = self.get_record(record_id)
        if not record:
            return None
        trimmed_prompt = prompt.strip()
        if trimmed_prompt:
            description = f"Generated description guided by: {trimmed_prompt}"
        else:
            description = "Generated updated description for the selected image."
        return self.update_description(record_id, description)

    def get_record(self, record_id: int) -> dict | None:
        for record in self.records:
            if record["id"] == record_id:
                return record
        return None


def extract_multipart_field(body: bytes, field_name: str) -> str | None:
    text = body.decode("latin1", errors="ignore")
    match = re.search(rf'name="{re.escape(field_name)}"\r\n\r\n([^\r\n]+)', text)
    if match:
        return match.group(1).strip()
    return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    state: MockState

    def log_message(self, *_args) -> None:
        return

    def _send_json(self, status: int, payload: dict | list) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, status: int, payload: bytes, mime_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _not_found(self) -> None:
        self._send_json(404, {"error": "Image record not found."})

    def _bad_request(self, message: str) -> None:
        self._send_json(400, {"error": message})

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self._send_json(200, {"status": "ok"})
            return

        if parsed.path == "/app-info":
            self._send_json(
                200,
                {
                    "aiModelId": "mock-ui-test-model",
                    "recordCount": len(self.state.records),
                },
            )
            return

        if parsed.path == "/images":
            search = parse_qs(parsed.query).get("search", [""])[0]
            self._send_json(200, self.state.list_records(search))
            return

        detail_match = re.fullmatch(r"/images/(\d+)", parsed.path)
        if detail_match:
            record = self.state.get_record(int(detail_match.group(1)))
            if not record:
                self._not_found()
                return
            self._send_json(200, record)
            return

        content_match = re.fullmatch(r"/images/(\d+)/content", parsed.path)
        if content_match:
            record = self.state.get_record(int(content_match.group(1)))
            if not record:
                self._not_found()
                return
            self._send_bytes(200, self.state.image_bytes, record["mimeType"])
            return

        self._not_found()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))

        if parsed.path == "/images":
            image_name = extract_multipart_field(body, "image_name") or "Uploaded From Smoke Test"
            description = extract_multipart_field(body, "description") or ""
            if not description.strip():
                self._bad_request("Image description is required.")
                return
            record = self.state.create_uploaded_record(image_name, description)
            self._send_json(201, record)
            return

        if parsed.path == "/descriptions/generate-upload":
            prompt = extract_multipart_field(body, "prompt") or ""
            if prompt.strip():
                description = f"Generated upload description guided by: {prompt.strip()}"
            else:
                description = "Generated upload description for the selected image."
            self._send_json(
                200,
                {
                    "description": description,
                    "detectedLanguage": "en",
                },
            )
            return

        generate_description_match = re.fullmatch(r"/images/(\d+)/description/generate", parsed.path)
        if generate_description_match:
            record_id = int(generate_description_match.group(1))
            try:
                payload = json.loads(body.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                payload = {}
            record = self.state.generate_description(record_id, str(payload.get("prompt", "")))
            if not record:
                self._not_found()
                return
            self._send_json(200, record)
            return

        insight_match = re.fullmatch(r"/images/(\d+)/insights", parsed.path)
        if insight_match:
            record = self.state.get_record(int(insight_match.group(1)))
            if not record:
                self._not_found()
                return
            self._send_json(
                200,
                {
                    "detectedLanguage": "en",
                    "text": (
                        "Smoke insight for uploaded image.\n\n"
                        "- **Main subject:** The uploaded fixture renders correctly.\n"
                        "- **Context:** The stored description is available to the model.\n"
                        "- **Formatting:** Bold text, blank lines, and bullet points should stay intact.\n\n"
                        "In short, **markdown structure should remain readable.**"
                    ),
                },
            )
            return

        self._not_found()

    def do_PUT(self) -> None:
        parsed = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))

        update_description_match = re.fullmatch(r"/images/(\d+)/description", parsed.path)
        if not update_description_match:
            self._not_found()
            return

        record_id = int(update_description_match.group(1))
        try:
            payload = json.loads(body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            payload = {}
        description = str(payload.get("description", "")).strip()
        if not description:
            self._bad_request("Image description is required.")
            return
        record = self.state.update_description(record_id, description)
        if not record:
            self._not_found()
            return
        self._send_json(200, record)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: mock_backend_server.py <port> <image-path>")

    port = int(sys.argv[1])
    image_path = Path(sys.argv[2]).expanduser().resolve()
    Handler.state = MockState(image_path)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    host, allocated_port = server.server_address
    print(f"http://{host}:{allocated_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
