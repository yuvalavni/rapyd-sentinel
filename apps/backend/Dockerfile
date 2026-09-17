FROM python:3.12-alpine

WORKDIR /app
COPY server.py /app/server.py

USER nobody
EXPOSE 8080
ENV PORT=8080

CMD ["python", "-u", "/app/server.py"]
