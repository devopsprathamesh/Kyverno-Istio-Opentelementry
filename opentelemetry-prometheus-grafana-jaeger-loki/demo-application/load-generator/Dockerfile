FROM python:3.13.5-slim

RUN groupadd --gid 10001 appuser && \
    useradd --uid 10001 --gid appuser --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY loadgen.py .

USER 10001:10001
ENTRYPOINT ["python", "loadgen.py"]
