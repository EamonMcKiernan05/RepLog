FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml README.md ./
COPY lift_sync ./lift_sync

RUN pip install --no-cache-dir .

# Data lives on a bind mount; the service never writes anywhere else.
ENV LIFT_SYNC_DATA_DIR=/data
VOLUME ["/data"]

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/v1/health', timeout=3).status==200 else 1)"

CMD ["uvicorn", "lift_sync.app:app", "--host", "0.0.0.0", "--port", "8080"]
