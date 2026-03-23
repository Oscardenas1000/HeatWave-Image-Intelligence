CREATE TABLE IF NOT EXISTS {{FULL_TABLE_NAME}} (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    image_name VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    base64_payload LONGTEXT NOT NULL,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_image_assets_name_created_at (image_name, created_at, id),
    KEY idx_image_assets_created_at (created_at, id)
) ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_0900_ai_ci
COMMENT='Base64 image registry for manual upload and review'
