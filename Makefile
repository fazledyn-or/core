export

SHELL = /bin/bash
PYTHON ?= python
PIP ?= pip
LOG_LEVEL = INFO
PYTHONIOENCODING=utf8
TESTDIR = $(CURDIR)/tests
PYTEST_ARGS = --continue-on-collection-errors

SPHINX_APIDOC =

BUILD_ORDER = ocrd_utils ocrd_models ocrd_modelfactory ocrd_validators ocrd_network ocrd
reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))

PEP_440_PATTERN := '([1-9][0-9]*!)?(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*((a|b|rc)(0|[1-9][0-9]*))?(\.post(0|[1-9][0-9]*))?(\.dev(0|[1-9][0-9]*))?'
OCRD_VERSION != fgrep version= ocrd_utils/setup.py | grep -Eo $(PEP_440_PATTERN)

# BEGIN-EVAL makefile-parser --make-help Makefile

help:
	@echo ""
	@echo "  Targets"
	@echo ""
	@echo "    deps-cuda      Dependencies for deployment with GPU support via Conda"
	@echo "    deps-ubuntu    Dependencies for deployment in an Ubuntu/Debian Linux"
	@echo "    deps-test      Install test python deps via pip"
	@echo "    install        (Re)install the tool"
	@echo "    install-dev    Install with pip install -e"
	@echo "    uninstall      Uninstall the tool"
	@echo "    generate-page  Regenerate python code from PAGE XSD"
	@echo "    spec           Copy JSON Schema, OpenAPI from OCR-D/spec"
	@echo "    assets         Setup test assets"
	@echo "    test           Run all unit tests"
	@echo "    docs           Build documentation"
	@echo "    docs-clean     Clean docs"
	@echo "    docs-coverage  Calculate docstring coverage"
	@echo "    docker         Build docker image"
	@echo "    docker-cuda    Build docker image for GPU / CUDA"
	@echo "    pypi           Build wheels and source dist and twine upload them"
	@echo ""
	@echo "  Variables"
	@echo ""
	@echo "    DOCKER_TAG         Docker target image tag. Default: '$(DOCKER_TAG)'."
	@echo "    DOCKER_BASE_IMAGE  Docker source image tag. Default: '$(DOCKER_BASE_IMAGE)'."
	@echo "    DOCKER_ARGS        Additional arguments to docker build. Default: '$(DOCKER_ARGS)'"
	@echo "    PIP_INSTALL        pip install command. Default: $(PIP_INSTALL)"
	@echo "    PYTEST_ARGS        arguments for pytest. Default: $(PYTEST_ARGS)"

# END-EVAL

# pip install command. Default: $(PIP_INSTALL)
PIP_INSTALL ?= $(PIP) install

deps-cuda: CONDA_EXE ?= /usr/local/bin/conda
deps-cuda: export CONDA_PREFIX ?= /conda
deps-cuda: PYTHON_PREFIX != $(PYTHON) -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])'
deps-cuda:
	curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba
	mv bin/micromamba $(CONDA_EXE)
# Install Conda system-wide (for interactive / login shells)
	echo 'export MAMBA_EXE=$(CONDA_EXE) MAMBA_ROOT_PREFIX=$(CONDA_PREFIX) CONDA_PREFIX=$(CONDA_PREFIX) PATH=$(CONDA_PREFIX)/bin:$$PATH' >> /etc/profile.d/98-conda.sh
	mkdir -p $(CONDA_PREFIX)/lib $(CONDA_PREFIX)/include
	echo $(CONDA_PREFIX)/lib >> /etc/ld.so.conf.d/conda.conf
# Get CUDA toolkit, including compiler and libraries with dev,
# however, the Nvidia channels do not provide (recent) cudnn (needed for Torch, TF etc):
#MAMBA_ROOT_PREFIX=$(CONDA_PREFIX) \
#conda install -c nvidia/label/cuda-11.8.0 cuda && conda clean -a
#
# The conda-forge channel has cudnn and cudatoolkit but no cudatoolkit-dev anymore (and we need both!),
# so let's combine nvidia and conda-forge (will be same lib versions, no waste of space),
# but omitting cuda-cudart-dev and cuda-libraries-dev (as these will be pulled by pip for torch anyway):
	MAMBA_ROOT_PREFIX=$(CONDA_PREFIX) \
	conda install -c nvidia/label/cuda-11.8.0 \
	                 cuda-nvcc \
	                 cuda-cccl \
	 && conda clean -a \
	 && find $(CONDA_PREFIX) -name "*_static.a" -delete
#conda install -c conda-forge \
#          cudatoolkit=11.8.0 \
#          cudnn=8.8.* && \
#conda clean -a && \
#find $(CONDA_PREFIX) -name "*_static.a" -delete
#
# Since Torch will pull in the CUDA libraries (as Python pkgs) anyway,
# let's jump the shark and pull these via NGC index directly,
# but then share them with the rest of the system so native compilation/linking
# works, too:
	$(PIP) install nvidia-pyindex \
	 && $(PIP) install nvidia-cudnn-cu11==8.6.0.163 \
	                   nvidia-cublas-cu11 \
	                   nvidia-cusparse-cu11 \
	                   nvidia-cusolver-cu11 \
	                   nvidia-curand-cu11 \
	                   nvidia-cufft-cu11 \
	                   nvidia-cuda-runtime-cu11 \
	                   nvidia-cuda-nvrtc-cu11 \
	 && for pkg in cudnn cublas cusparse cusolver curand cufft cuda_runtime cuda_nvrtc; do \
	        for lib in $(PYTHON_PREFIX)/nvidia/$$pkg/lib/lib*.so.*; do \
	            base=`basename $$lib`; \
	            ln -s $$lib $(CONDA_PREFIX)/lib/$$base.so; \
	            ln -s $$lib $(CONDA_PREFIX)/lib/$${base%.so.*}.so; \
	        done \
	     && ln -s $(PYTHON_PREFIX)/nvidia/$$pkg/include/* $(CONDA_PREFIX)/include/; \
	    done \
	 && ldconfig
# gputil/nvidia-smi would be nice, too – but that drags in Python as a conda dependency...

# Dependencies for deployment in an ubuntu/debian linux
deps-ubuntu:
	apt-get install -y python3 imagemagick libgeos-dev

# Install test python deps via pip
deps-test:
	$(PIP) install -U pip
	$(PIP) install -r requirements_test.txt

# (Re)install the tool
install:
#	$(PIP_INSTALL) $(BUILD_ORDER:%=./%/dist/ocrd$*(OCRD_VERSION)*.whl)
	$(foreach MODULE,$(BUILD_ORDER),$(PIP_INSTALL) ./$(MODULE) &&) echo done
	@# workaround for shapely#1598
	$(PIP) config set global.no-binary shapely

# Install with pip install -e
install-dev: uninstall
	$(MAKE) install PIP_INSTALL="$(PIP) install -e"

# Uninstall the tool
uninstall:
	$(PIP) uninstall -y $(call reverse,$(BUILD_ORDER))

# Regenerate python code from PAGE XSD
generate-page: GDS_PAGE = ocrd_models/ocrd_models/ocrd_page_generateds.py
generate-page: GDS_PAGE_USER = ocrd_models/ocrd_page_user_methods.py
generate-page: repo/assets
	generateDS \
		-f \
		--root-element='PcGts' \
		-o $(GDS_PAGE) \
		--silence \
		--export "write etree" \
		--disable-generatedssuper-lookup \
		--user-methods=$(GDS_PAGE_USER) \
		ocrd_validators/ocrd_validators/page.xsd
	# hack to prevent #451: enum keys will be strings
	sed -i 's/(Enum):$$/(str, Enum):/' $(GDS_PAGE)
	# hack to ensure output has pc: prefix
	@#sed -i "s/namespaceprefix_=''/namespaceprefix_='pc:'/" $(GDS_PAGE)
	sed -i 's/_nsprefix_ = None/_nsprefix_ = "pc"/' $(GDS_PAGE)
	# hack to ensure child nodes also have pc: prefix...
	sed -i 's/.*_nsprefix_ = child_.prefix$$//' $(GDS_PAGE)
	# replace the need for six since we target python 3.6+
	sed -i 's/from six.moves/from itertools/' $(GDS_PAGE)

#
# Repos
#
.PHONY: repos always-update
repos: repo/assets repo/spec


# Update OCR-D/assets and OCR-D/spec resp.
repo/assets repo/spec: always-update
	git submodule sync --recursive $@
	if git submodule status --recursive $@ | grep -qv '^ '; then \
		git submodule update --init --recursive $@ && \
		touch $@; \
	fi

#
# Spec
#

.PHONY: spec
# Copy JSON Schema, OpenAPI from OCR-D/spec
spec: repo/spec
	cp repo/spec/ocrd_tool.schema.yml ocrd_validators/ocrd_validators/ocrd_tool.schema.yml
	cp repo/spec/bagit-profile.yml ocrd_validators/ocrd_validators/bagit-profile.yml

#
# Assets
#

# Setup test assets
assets: repo/assets
	rm -rf $(TESTDIR)/assets
	mkdir -p $(TESTDIR)/assets
	cp -r repo/assets/data/* $(TESTDIR)/assets


#
# Tests
#

.PHONY: test
# Run all unit tests
test: assets
	$(PYTHON) \
		-m pytest $(PYTEST_ARGS) --durations=10\
		--ignore-glob="$(TESTDIR)/**/*bench*.py" \
		$(TESTDIR)
	cd ocrd_utils ; $(PYTHON) -m pytest --continue-on-collection-errors -k TestLogging -k TestDecorators $(TESTDIR)

benchmark:
	$(PYTHON) -m pytest $(TESTDIR)/model/test_ocrd_mets_bench.py

benchmark-extreme:
	$(PYTHON) -m pytest $(TESTDIR)/model/*bench*.py

test-profile:
	$(PYTHON) -m cProfile -o profile $$(which pytest)
	$(PYTHON) analyze_profile.py

coverage: assets
	coverage erase
	make test PYTHON="coverage run"
	coverage report
	coverage html

#
# Documentation
#

.PHONY: docs
# Build documentation
docs:
	for mod in $(BUILD_ORDER);do sphinx-apidoc -f -M -e \
		-o docs/api/$$mod $$mod/$$mod \
		'ocrd_models/ocrd_models/ocrd_page_generateds.py' \
		;done
	cd docs ; $(MAKE) html

docs-push: gh-pages docs
	cp -r docs/build/html/* gh-pages
	cd gh-pages; git add . && git commit -m 'Updated docs $$(date)' && git push

# Clean docs
docs-clean:
	cd gh-pages ; rm -rf *
	cd docs ; rm -rf _build api/ocrd api/ocrd_*

# Calculate docstring coverage
docs-coverage:
	for mod in $(BUILD_ORDER);do docstr-coverage $$mod/$$mod -e '.*(ocrd_page_generateds|/ocrd/cli/).*';done
	for mod in $(BUILD_ORDER);do echo "# $$mod"; docstr-coverage -v1 $$mod/$$mod -e '.*(ocrd_page_generateds|/ocrd/cli/).*'|sed 's/^/\t/';done

gh-pages:
	git clone --branch gh-pages https://github.com/OCR-D/core gh-pages

#
# Clean up
#

pyclean:
	rm -f **/*.pyc
	find . -name '__pycache__' -exec rm -rf '{}' \;
	rm -rf .pytest_cache

#
# Docker
#

.PHONY: docker docker-cuda

# Additional arguments to docker build. Default: '$(DOCKER_ARGS)'
DOCKER_ARGS = 

# Build docker image
docker: DOCKER_BASE_IMAGE = ubuntu:20.04
docker: DOCKER_TAG = ocrd/core
docker: DOCKER_FILE = Dockerfile

docker-cuda: DOCKER_BASE_IMAGE = ocrd/core
docker-cuda: DOCKER_TAG = ocrd/core-cuda
docker-cuda: DOCKER_FILE = Dockerfile.cuda

docker-cuda: docker

docker docker-cuda: 
	docker build --progress=plain -f $(DOCKER_FILE) -t $(DOCKER_TAG) --build-arg BASE_IMAGE=$(DOCKER_BASE_IMAGE) $(DOCKER_ARGS) .

# Build wheels and source dist and twine upload them
pypi: uninstall install
	$(PIP) install build
	$(foreach MODULE,$(BUILD_ORDER),$(PYTHON) -m build -n ./$(MODULE) &&) echo done
	twine upload ocrd*/dist/ocrd*$(OCRD_VERSION)*{tar.gz,whl}
