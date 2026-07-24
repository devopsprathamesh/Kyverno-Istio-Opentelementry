# Pinned base image — see ../../config/versions.env DEMO_PYTHON_BASE_IMAGE.
# No registry push — built locally and imported directly into cluster
# node containerd by scripts/build-demo-images.sh. See
# docs/DECISIONS.md ADR-030.
FROM python:3.13.5-slim

RUN groupadd --gid 10001 appuser && \
    useradd --uid 10001 --gid appuser --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

USER 10001:10001
EXPOSE 8000

ENTRYPOINT ["python", "app.py"]
