# Imagen del Cloud Run Job. Fija la versión de la base (nunca `latest`).
FROM python:3.11.18-slim-bookworm
WORKDIR /app
COPY pyproject.toml ./
COPY sellout_gen ./sellout_gen
RUN pip install --no-cache-dir .
# Corre como usuario sin privilegios
RUN useradd --uid 10001 app
USER app
ENTRYPOINT ["python", "-m", "sellout_gen.main"]
