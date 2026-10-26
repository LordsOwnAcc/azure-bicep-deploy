import os
import socket
from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(message="Hello from azure-bicep-deploy",
                   host=socket.gethostname(),
                   version=os.getenv("APP_VERSION", "dev"))


@app.get("/health")
def health():
    return jsonify(status="ok"), 200


@app.get("/boom")  # deliberately returns 500 so you can test the 5xx alert
def boom():
    return jsonify(error="test failure"), 500
