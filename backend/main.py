from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, File, Form, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response

from backend.config import AppConfig, get_config
from backend.errors import AppError
from backend.images import ImageService
from backend.models import (
    AppInfo,
    DescriptionGenerationRequest,
    DescriptionUpdateRequest,
    ErrorResponse,
    GeneratedDescriptionResponse,
    ImageDetail,
    ImageSummary,
    InsightRequest,
    InsightResponse,
)
from backend.repository import MySQLImageRepository


def _validation_error_message(exc: RequestValidationError) -> str:
    messages = []
    for error in exc.errors():
        location = ".".join(str(part) for part in error.get("loc", ()) if part != "body")
        prefix = f"{location}: " if location else ""
        messages.append(f"{prefix}{error.get('msg', 'Invalid request.')}")
    return "; ".join(messages) or "Invalid request."


def create_app(
    *,
    config: AppConfig | None = None,
    repository: Any | None = None,
    image_service: ImageService | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        resolved_config = config or get_config()
        resolved_repository = repository or MySQLImageRepository(resolved_config)
        resolved_image_service = image_service or ImageService()
        app.state.config = resolved_config
        app.state.repository = resolved_repository
        app.state.image_service = resolved_image_service
        resolved_repository.ensure_schema_and_table()
        yield

    app = FastAPI(
        title="HeatWave Image Intelligence API",
        version="1.0.0",
        lifespan=lifespan,
    )

    @app.exception_handler(AppError)
    async def handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.message})

    @app.exception_handler(RequestValidationError)
    async def handle_request_validation(
        _: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(status_code=422, content={"error": _validation_error_message(exc)})

    @app.exception_handler(Exception)
    async def handle_unexpected_error(_: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(status_code=500, content={"error": str(exc) or "Internal server error."})

    def get_repository(request: Request):
        return request.app.state.repository

    def get_image_service(request: Request) -> ImageService:
        return request.app.state.image_service

    def get_app_config(request: Request) -> AppConfig:
        return request.app.state.config

    @app.get("/health", response_model=dict[str, str])
    async def healthcheck() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/app-info", response_model=AppInfo)
    async def app_info(
        repo=Depends(get_repository),
        app_config: AppConfig = Depends(get_app_config),
    ) -> AppInfo:
        return AppInfo(
            ai_model_id=app_config.ai_model_id,
            record_count=repo.count_records(),
        )

    @app.get(
        "/images",
        response_model=list[ImageSummary],
        responses={500: {"model": ErrorResponse}},
    )
    async def list_images(search: str = "", repo=Depends(get_repository)) -> list[dict[str, Any]]:
        return repo.list_records(search)

    @app.get(
        "/images/{record_id}",
        response_model=ImageDetail,
        responses={404: {"model": ErrorResponse}},
    )
    async def get_image(record_id: int, repo=Depends(get_repository)) -> dict[str, Any]:
        return repo.get_record_or_404(record_id)

    @app.get(
        "/images/{record_id}/content",
        responses={404: {"model": ErrorResponse}},
    )
    async def get_image_content(
        record_id: int,
        repo=Depends(get_repository),
        service: ImageService = Depends(get_image_service),
    ) -> Response:
        record = repo.get_record_or_404(record_id, include_payload=True)
        image_bytes, _, mime_hint = service.decode_base64_text(record["base64_payload"])
        media_type = mime_hint or str(record["mime_type"]) or "application/octet-stream"
        return Response(content=image_bytes, media_type=media_type)

    @app.post(
        "/images",
        response_model=ImageDetail,
        status_code=201,
        responses={400: {"model": ErrorResponse}},
    )
    async def create_image(
        image_name: str = Form(...),
        description: str = Form(""),
        file: UploadFile = File(...),
        repo=Depends(get_repository),
        service: ImageService = Depends(get_image_service),
    ) -> dict[str, Any]:
        image_bytes = await file.read()
        payload, _ = service.build_payload_from_upload(
            image_name=image_name,
            original_filename=file.filename or "uploaded-image",
            declared_mime_type=file.content_type,
            image_bytes=image_bytes,
        )
        return repo.create_image(payload, description=description)

    @app.post(
        "/descriptions/generate-upload",
        response_model=GeneratedDescriptionResponse,
        responses={400: {"model": ErrorResponse}},
    )
    async def generate_upload_description(
        prompt: str = Form(""),
        file: UploadFile = File(...),
        repo=Depends(get_repository),
        service: ImageService = Depends(get_image_service),
    ) -> GeneratedDescriptionResponse:
        image_bytes = await file.read()
        payload, _ = service.build_payload_from_upload(
            image_name="Generated Description Upload",
            original_filename=file.filename or "uploaded-image",
            declared_mime_type=file.content_type,
            image_bytes=image_bytes,
        )
        result = repo.generate_upload_description(
            base64_payload=payload.base64_payload,
            prompt=prompt,
        )
        return GeneratedDescriptionResponse(
            description=result.text,
            detected_language=result.detected_language,
        )

    @app.put(
        "/images/{record_id}/description",
        response_model=ImageDetail,
        responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    )
    async def update_image_description(
        record_id: int,
        request: DescriptionUpdateRequest,
        repo=Depends(get_repository),
    ) -> dict[str, Any]:
        return repo.update_image_description(record_id, description=request.description)

    @app.post(
        "/images/{record_id}/description/generate",
        response_model=ImageDetail,
        responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    )
    async def generate_image_description(
        record_id: int,
        request: DescriptionGenerationRequest,
        repo=Depends(get_repository),
    ) -> dict[str, Any]:
        return repo.generate_and_store_description(record_id, prompt=request.prompt)

    @app.post(
        "/images/{record_id}/insights",
        response_model=InsightResponse,
        responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    )
    async def create_insight(
        record_id: int,
        insight: InsightRequest,
        repo=Depends(get_repository),
    ) -> InsightResponse:
        result = repo.generate_image_insight_result(record_id, insight.prompt)
        return InsightResponse(
            text=result.text,
            detected_language=result.detected_language,
        )

    return app


app = create_app()
