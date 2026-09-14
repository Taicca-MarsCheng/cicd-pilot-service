FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

RUN addgroup --system app \
    && adduser --system --ingroup app app

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY --chown=app:app main.py ./

USER app
EXPOSE 8080

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 0 main:app"]

