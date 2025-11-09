FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/yassineaboukir/Asnlookup.git /opt/asnlookup
WORKDIR /opt/asnlookup

RUN pip install --no-cache-dir -r requirements.txt

ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "asnlookup.py"]
