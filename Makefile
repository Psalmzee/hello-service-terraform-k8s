.PHONY: run test docker-build docker-run tf-init tf-plan tf-apply tf-destroy fmt validate

APP_IMAGE ?= hello-service:local

run:
	uvicorn app.main:app --reload --port 8000

test:
	pip install -r app/requirements-dev.txt
	pytest -v

docker-build:
	docker build -t $(APP_IMAGE) .

docker-run:
	docker run --rm -p 8000:8000 $(APP_IMAGE)

tf-init:
	terraform -chdir=examples/basic init

tf-plan:
	terraform -chdir=examples/basic plan

tf-apply:
	terraform -chdir=examples/basic apply

tf-destroy:
	terraform -chdir=examples/basic destroy

fmt:
	terraform fmt -recursive

validate:
	terraform -chdir=modules/platform-app init -backend=false
	terraform -chdir=modules/platform-app validate
