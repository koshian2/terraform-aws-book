FROM python:3.14-slim
WORKDIR /demo
COPY pyproject.toml .
RUN --mount=from=ghcr.io/astral-sh/uv:0.12.24,source=/uv,target=/bin/uv uv pip compile --generate-hashes pyproject.toml -o /tmp/requirements.txt && pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt
COPY scripts/verify.py scripts/verify.py
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
CMD ["python", "scripts/verify.py"]
