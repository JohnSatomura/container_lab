FROM python:3.11-slim

RUN pip install --no-cache-dir ansible

RUN ansible-galaxy collection install arista.eos

WORKDIR /ansible
