.PHONY: test docs

all:
	@echo "Targets:"
	@echo ""
	@echo "   clean            Cleanup"
	@echo "   test             Run unit tests"
	@echo "   flake8           Run flake tests"
	@echo "   install          Local install"
	@echo "   publish          Clean build and publish to PyPI"
	@echo "   docs             Build and test docs"
	@echo ""

clean:
	rm -rf ./build
	rm -rf ./dist
	rm -rf ./crossbar.egg-info
	rm -rf ./.crossbar
	-find . -type d -name _trial_temp -exec rm -rf {} \;
	rm -rf ./tests
	rm -rf ./.tox
	rm -rf ./vers
	rm -f .coverage.*
	rm -f .coverage
	rm -rf ./htmlcov
	-rm -rf ./_trial*
	find . -name "*.db" -exec rm -f {} \;
	find . -name "*.pyc" -exec rm -f {} \;
	find . -name "*.log" -exec rm -f {} \;
	# Learn to love the shell! http://unix.stackexchange.com/a/115869/52500
	find . \( -name "*__pycache__" -type d \) -prune -exec rm -rf {} +


# Targets for Sphinx-based documentation
#
docs_clean:
	-rm -rf ./rtd/_build

docs_builds:
	sphinx-build -b html rtd rtd/_build

# spellcheck the docs
docs_spelling:
	sphinx-build -b spelling -d rtd/_build/doctrees rtd rtd/_build/spelling


# call this in a fresh virtualenv to update our frozen requirements.txt!
freeze: clean
	pip install -U virtualenv
	virtualenv vers
	vers/bin/pip install -r requirements-min.txt
	vers/bin/pip freeze --all | grep -v -e "wheel" -e "pip" -e "distribute" > requirements-pinned.txt
	vers/bin/pip install hashin
	rm requirements.txt
	cat requirements-pinned.txt | xargs vers/bin/hashin > requirements.txt

wheel:
	LMDB_FORCE_CFFI=1 SODIUM_INSTALL=bundled pip wheel --require-hashes --wheel-dir ./wheels -r requirements.txt

# install for development, using pinned dependencies, and including dev-only dependencies
install:
	-pip uninstall -y crossbar
	pip install --no-cache --upgrade -r requirements-dev.txt
	pip install -e .
	@python -c "import crossbar; print('*** crossbar-{} ***'.format(crossbar.__version__))"

# install using pinned/hashed dependencies, as we do for packaging
install_pinned:
	-pip uninstall -y crossbar
	LMDB_FORCE_CFFI=1 SODIUM_INSTALL=bundled pip install --ignore-installed --require-hashes -r requirements.txt
	pip install .
	@python -c "import crossbar; print('*** crossbar-{} ***'.format(crossbar.__version__))"

# upload to our internal deployment system
upload: clean
	python setup.py bdist_wheel
	aws s3 cp dist/*.whl s3://fabric-deploy/

# publish to PyPI
publish: clean
	python setup.py sdist bdist_wheel
	twine upload dist/*

test_trial: flake8
	trial crossbar

test_full:
	crossbar \
		--personality=standalone \
		--debug-lifecycle \
		--debug-programflow\
		start \
		--cbdir=./test/full/.crossbar

test_manhole:
	ssh -vvv -p 6022 oberstet@localhost

gen_ssh_keys:
#	ssh-keygen -t ed25519 -f test/full/.crossbar/ssh_host_ed25519_key
	ssh-keygen -t rsa -b 4096 -f test/full/.crossbar/ssh_host_rsa_key

test_coverage:
	tox -e coverage .

test:
	tox -e sphinx,flake8,py36-unpinned-trial,py36-cli,py36-examples,coverage .

test_bandit:
	tox -e bandit .

test_cli:
	./test/test_cli.sh

test_cli_tox:
	tox -e py36-cli .

test_examples:
	tox -e py36-examples .

test_mqtt:
#	trial crossbar.adapter.mqtt.test.test_wamp
	trial crossbar.adapter.mqtt.test.test_wamp.MQTTAdapterTests.test_basic_publish

test_reactors:
	clear
	-crossbar version --loglevel=debug
	-crossbar --reactor="select" version --loglevel=debug
	-crossbar --reactor="poll" version --loglevel=debug
	-crossbar --reactor="epoll" version --loglevel=debug
	-crossbar --reactor="kqueue" version --loglevel=debug
	-crossbar --reactor="iocp" version --loglevel=debug

full_test: clean flake8
	trial crossbar

# This will run pep8, pyflakes and can skip lines that end with # noqa
flake8:
	flake8 --ignore=E402,F405,E501,E722,E741,E731,N801,N802,N803,N805,N806 crossbar

flake8_stats:
	flake8 --statistics --max-line-length=119 -qq crossbar

version:
	PYTHONPATH=. python -m crossbar.controller.cli version

pyflakes:
	pyflakes crossbar

pep8:
	pep8 --statistics --ignore=E501 -qq .

pep8_show_e231:
	pep8 --select=E231 --show-source

autopep8:
	autopep8 -ri --aggressive --ignore=E501 .

pylint:
	pylint -d line-too-long,invalid-name crossbar

find_classes:
	find crossbar -name "*.py" -exec grep -Hi "^class" {} \; | grep -iv test

# sudo apt install gource ffmpeg
gource:
	gource \
	--path . \
	--seconds-per-day 0.15 \
	--title "crossbar" \
	-1280x720 \
	--file-idle-time 0 \
	--auto-skip-seconds 0.75 \
	--multi-sampling \
	--stop-at-end \
	--highlight-users \
	--hide filenames,mouse,progress \
	--max-files 0 \
	--background-colour 000000 \
	--disable-bloom \
	--font-size 24 \
	--output-ppm-stream - \
	--output-framerate 30 \
	-o - \
	| ffmpeg \
	-y \
	-r 60 \
	-f image2pipe \
	-vcodec ppm \
	-i - \
	-vcodec libx264 \
	-preset ultrafast \
	-pix_fmt yuv420p \
	-crf 1 \
	-threads 0 \
	-bf 0 \
	crossbar.mp4
