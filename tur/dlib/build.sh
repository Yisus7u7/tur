TERMUX_PKG_HOMEPAGE=http://dlib.net/
TERMUX_PKG_DESCRIPTION="a modern C++ toolkit containing machine learning algorithms and tools for creating complex software in C++ to solve real world problems"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux-user-repository"
TERMUX_PKG_VERSION=19.24
TERMUX_PKG_SRCURL=https://github.com/davisking/dlib/archive/refs/tags/v$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SHA256=3cc42e84c7b1bb926c6451a21ad1595f56c5b10be3a1d7aa2f3c716a25b7ae39
TERMUX_PKG_DEPENDS="libx11, libxcb, openblas, python"

termux_step_pre_configure() {
	termux_setup_cmake
	termux_setup_ninja

	_PYTHON_VERSION=$(. $TERMUX_SCRIPTDIR/packages/python/build.sh; echo $_MAJOR_VERSION)

	if $TERMUX_ON_DEVICE_BUILD; then
		termux_error_exit "Package '$TERMUX_PKG_NAME' is not available for on-device builds."
	fi

	termux_setup_python_crossenv
	pushd $TERMUX_PYTHON_CROSSENV_SRCDIR
	_CROSSENV_PREFIX=$TERMUX_PKG_BUILDDIR/python-crossenv-prefix
	python${_PYTHON_VERSION} -m crossenv \
		$TERMUX_PREFIX/bin/python${_PYTHON_VERSION} \
		${_CROSSENV_PREFIX}
	popd
	. ${_CROSSENV_PREFIX}/bin/activate

	LDFLAGS+=" -lpython${_PYTHON_VERSION}"
}

termux_step_configure() {
	if [ "$TERMUX_CMAKE_BUILD" = Ninja ]; then
		MAKE_PROGRAM_PATH=$(command -v ninja)
	else
		MAKE_PROGRAM_PATH=$(command -v make)
	fi
	BUILD_TYPE=Release
	test "$TERMUX_DEBUG_BUILD" == "true" && BUILD_TYPE=Debug
	CMAKE_PROC=$TERMUX_ARCH
	test $CMAKE_PROC == "arm" && CMAKE_PROC='armv7-a'
	CPPFLAGS+=" -DPNG_ARM_NEON_OPT=0"
}

termux_step_make() {
	export PYTHONPATH=$TERMUX_PREFIX/lib/python${_PYTHON_VERSION}/site-packages
	pushd $TERMUX_PKG_SRCDIR
	python setup.py install --force \
			--prefix $TERMUX_PREFIX \
			-G $TERMUX_CMAKE_BUILD \
			--set CMAKE_AR="$(command -v $AR)" \
			--set CMAKE_UNAME="$(command -v uname)" \
			--set CMAKE_RANLIB="$(command -v $RANLIB)" \
			--set CMAKE_STRIP="$(command -v $STRIP)" \
			--set CMAKE_BUILD_TYPE=$BUILD_TYPE \
			--set CMAKE_C_FLAGS="$CFLAGS $CPPFLAGS" \
			--set CMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS" \
			--set CMAKE_FIND_ROOT_PATH=$TERMUX_PREFIX \
			--set CMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
			--set CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
			--set CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
			--set CMAKE_INSTALL_PREFIX=$TERMUX_PREFIX \
			--set CMAKE_INSTALL_LIBDIR=$TERMUX_PREFIX/lib \
			--set CMAKE_MAKE_PROGRAM=$MAKE_PROGRAM_PATH \
			--set CMAKE_SKIP_INSTALL_RPATH=ON \
			--set CMAKE_USE_SYSTEM_LIBRARIES=True \
			--set BUILD_TESTING=OFF \
			--set CMAKE_CROSSCOMPILING=True \
			--set CMAKE_SYSTEM_NAME=Linux \
			--set SSE4_IS_AVAILABLE_ON_HOST=0 \
			--set AVX_IS_AVAILABLE_ON_HOST=0 \
			--set ARM_NEON_IS_AVAILABLE=0
	popd
}

termux_step_make_install() {
	pushd $PYTHONPATH
	_EGGDIR=
	for f in dlib-${TERMUX_PKG_VERSION}.0-py${_PYTHON_VERSION}-linux-*.egg; do
		# .egg is a zip file or a directory
		if [ -f "$f" ] || [ -d "$f" ]; then
			_EGGDIR="$f"
			break
		fi
	done
	test -n "${_EGGDIR}"
	# XXX: Fix the EXT_SUFFIX. More investigation is needed to find the underlying cause.
	pushd "${_EGGDIR}"
	local old_suffix=".cpython-310-$TERMUX_HOST_PLATFORM.so"
	local new_suffix=".cpython-310.so"

	find . \
		-name '*'"$old_suffix" \
		-exec sh -c '_f="{}"; mv -- "$_f" "${_f%'"$old_suffix"'}'"$new_suffix"'"' \;
	popd
	popd
}

termux_step_post_make_install() {
	# Delete the easy-install related files, since we use postinst/prerm to handle it.
	pushd $TERMUX_PREFIX
	rm -rf lib/python${_PYTHON_VERSION}/site-packages/__pycache__
	rm -rf lib/python${_PYTHON_VERSION}/site-packages/easy-install.pth
	rm -rf lib/python${_PYTHON_VERSION}/site-packages/site.py
	popd
}

termux_step_create_debscripts() {
	cat <<- EOF > ./postinst
	#!$TERMUX_PREFIX/bin/sh
	echo "Installing $TERMUX_PKG_NAME..."
	echo "./${_EGGDIR}" >> $TERMUX_PREFIX/lib/python${_PYTHON_VERSION}/site-packages/easy-install.pth
	EOF

	cat <<- EOF > ./prerm
	#!$TERMUX_PREFIX/bin/sh
	echo "Removing $TERMUX_PKG_NAME..."
	sed -i "/\.\/${_EGGDIR//./\\.}/d" $TERMUX_PREFIX/lib/python${_PYTHON_VERSION}/site-packages/easy-install.pth
	EOF
}
