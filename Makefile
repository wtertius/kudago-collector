cli:
	docker-compose exec collector perl -d ./collector/collect.pl
run:
	docker-compose exec collector perl ./collector/collect.pl
bash:
	docker-compose exec collector bash
test:
	docker-compose exec collector bash -c "prove ./collector/lib/*/"
