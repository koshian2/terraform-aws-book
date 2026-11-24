FROM python:3.14-slim
WORKDIR /demo
COPY requirements.txt .
RUN pip install --no-cache-dir --require-hashes -r requirements.txt
COPY scripts/verify.py scripts/verify.py
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
CMD ["python", "scripts/verify.py"]
