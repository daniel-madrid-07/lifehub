import os

from sqlmodel import Session, SQLModel, create_engine

DB_PATH = os.environ.get("LIFE_HUB_DB", os.path.join(os.path.dirname(__file__), "..", "life.db"))
engine = create_engine(f"sqlite:///{DB_PATH}", connect_args={"check_same_thread": False})


def init_db():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session
