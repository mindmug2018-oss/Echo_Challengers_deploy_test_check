# ~/project1-aws/ansible/roles/fastapi/files/app/main.py

import os
import socket
from fastapi import FastAPI, HTTPException
from sqlalchemy import create_engine, text
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Project1 AWS API")

# Prometheus 메트릭 수집 활성화
Instrumentator().instrument(app).expose(app)

# ─── 1. 클라우드 네이티브: 환경 변수 기반 DB 연결 ───
# 하드코딩된 IP 대신 OS 환경 변수에서 값을 가져옵니다.
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASS = os.getenv("DB_PASS", "apppass123")
DB_HOST = os.getenv("DB_HOST", "localhost")  # AWS 배포 시 Ansible이 템플릿을 통해 동적 주입
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "appdb")

DB_URL = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# DB 엔진 생성 (커넥션 풀 유지 및 상태 체크)
engine = create_engine(DB_URL, pool_pre_ping=True)

# ─── 2. AWS ALB Health Check 엔드포인트 ───
@app.get("/health")
def health_check():
    """
    단순 서버 생존 여부뿐만 아니라, DB 연결 상태까지 체크하여
    ALB가 완벽히 정상적인 인스턴스로만 트래픽을 보내도록 고도화합니다.
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        db_status = f"disconnected ({str(e)})"
        # DB 연결 실패 시 500 에러를 반환해 ALB가 트래픽을 차단하게 할 수도 있습니다.
        # raise HTTPException(status_code=500, detail="Database connection failed")

    return {
        "status": "ok", 
        "server": socket.gethostname(),
        "database": db_status
    }

# ─── 3. 비즈니스 로직 ───
@app.get("/items")
def get_items():
    try:
        with engine.connect() as conn:
            rows = conn.execute(text("SELECT * FROM items")).fetchall()
            return {"items": [dict(r._mapping) for r in rows]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/items")
def create_item(name: str):
    try:
        with engine.connect() as conn:
            conn.execute(
                text("INSERT INTO items (name, server) VALUES (:n, :s)"),
                {"n": name, "s": socket.gethostname()}
            )
            conn.commit()
        return {"created": name, "by": socket.gethostname()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))