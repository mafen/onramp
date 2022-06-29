# include .env variable in the current environment
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# any disabled-*.yml docker-compose files will be ignored
disabled_files := $(wildcard services-enabled/disabled-*.yml)
# all other *.yml files in the current directory will be included 
# when running make commands that call docker compose
compose_files := $(filter-out $(disabled_files), $(wildcard services-enabled/*.yml)) 
args := -f docker-compose.yml $(foreach file, $(compose_files), -f $(file))
args_service := --project-directory ./ -f 

# get the boxes ip address and the current users id and group id
export HOSTIP := $(shell ip route get 1.1.1.1 | grep -oP 'src \K\S+')
export PUID 	:= $(shell id -u)
export PGID 	:= $(shell id -g)
export HOST_NAME := $(or $(HOST_NAME), $(shell hostname))

# check if we should use docker-compose or docker compose
ifeq (, $(shell which docker-compose))
	DOCKER_COMPOSE := docker compose
else
	DOCKER_COMPOSE := docker-compose
endif

# look for the second target word passed to make
PASSED_SERVICE := $(word 2,$(MAKECMDGOALS))

# used to look for the file in the services-enabled folder when start-service is used 
SERVICE_FILE = ./services-enabled/$(PASSED_SERVICE).yml

# use the rest as arguments as empty targets aka: MAGIC
EMPTY_TARGETS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(EMPTY_TARGETS):;@:)

# this is the default target run if no other targets are passed to make
# i.e. if you just type: make
start: build
	$(DOCKER_COMPOSE) $(args) up -d --force-recreate

start-service: build
	$(DOCKER_COMPOSE) $(args_service) $(SERVICE_FILE) up -d --force-recreate

up: build
	$(DOCKER_COMPOSE) $(args) up --force-recreate

down: 
	$(DOCKER_COMPOSE) $(args) down

start-staging: build
	ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory $(DOCKER_COMPOSE) $(args) up -d --force-recreate
	@echo "waiting 30 seconds for cert DNS propogation..."
	@sleep 30
	@echo "open https://$(HOST_NAME).$(HOST_DOMAIN)/traefik in a browser"
	@echo "and check that you have a staging cert from LetsEncrypt!"
	@echo ""
	@echo "if you don't get the write cert run the following command and look for error messages:"
	@echo "$(DOCKER_COMPOSE) logs | grep acme"
	@echo ""
	@echo "otherwise run the following command if you successfully got a staging certificate:"
	@echo "make down-staging"

down-staging:
	$(DOCKER_COMPOSE) $(args) down
	$(MAKE) clean-acme

clean-acme:
	@echo "cleaning up staging certificates"
	sudo rm etc/letsencrypt/acme.json

pull:
	$(DOCKER_COMPOSE) $(args) pull

logs:
	$(DOCKER_COMPOSE) $(args) logs -f

restart: down start

update: down pull start

exec:
	$(DOCKER_COMPOSE) $(args) exec $(PASSED_SERVICE) sh

build: .env etc/prometheus/conf

.env:
	cp .env.sample .env
	nano .env

etc/prometheus/conf:
	mkdir -p etc/prometheus/conf
	cp --no-clobber --recursive	etc/prometheus/conf-originals/* etc/prometheus/conf

list-games:
	@ls -1 ./services-available/games | sed -n 's/\.yml$ //p'

list-services:
	@ls -1 ./services-available/ | sed -e 's/\.yml$ //'

list-external:
	@ls -1 ./etc/traefik/available/ | sed -e 's/\.yml$ //'

enable-game:
	@ln -s ../services-available/games/$(PASSED_SERVICE).yml ./services-enabled/$(PASSED_SERVICE).yml || true

enable-service:
	@ln -s ../services-available/$(PASSED_SERVICE).yml ./services-enabled/$(PASSED_SERVICE).yml || true

enable-external:
	@ln -s ../available/$(PASSED_SERVICE).yml ./etc/traefik/enabled/$(PASSED_SERVICE).yml || true

disable-game: disable-service

disable-service:
	rm ./services-enabled/$(PASSED_SERVICE).yml

disable-external:
	rm ./etc/traefik/enabled/$(PASSED_SERVICE).yml

install-node-exporter:
	curl -s https://gist.githubusercontent.com/ilude/2cf7a3b7712378c6b9bcf1e1585bf70f/raw/setup_node_exporter.sh?$(date +%s) | /bin/bash -s | tee build.log

echo:
	@echo $(args)

echo-service:
	@echo $(args_service) $(SERVICE_FILE)

env:
	env | sort