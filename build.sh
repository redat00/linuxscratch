#!/bin/bash

KERNEL_VERSION=6.7.1
GLIBC_VERSION=2.38
BUSYBOX_VERSION=1.36.1
BASH_VERSION=5.2.21
NANO_VERSION=7.2
OPENSSL_VERSION=3.2.0
OPENRC_VERSION=0.53

init_build () {
	mkdir -p initrd src
	cd initrd
		mkdir sys proc dev etc bin lib sbin var
	cd ..
}

build_linux_kernel () {
	# Building the kernel
	KERNEL_MAJOR=$(echo $KERNEL_VERSION | sed 's/\([0-9]*\)[^0-9].*/\1/')
	wget https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz
	tar -xf linux-$KERNEL_VERSION.tar.xz
	cd linux-$KERNEL_VERSION
		make defconfig
		#sed 's/^.*CONFIG_INITRAMFS_SOURCE[^_].*/CONFIG_INITRAMFS_SOURCE="y"/g' -i .config
		make -j $(nproc) || exit
	cd ..
	cp linux-$KERNEL_VERSION/arch/x86_64/boot/bzImage ../.
}

build_glibc () {
	wget	https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.gz
	tar -xzf glibc-${GLIBC_VERSION}.tar.gz
	mkdir build_glibc
	cd build_glibc
		../glibc-${GLIBC_VERSION}/configure --prefix=${PWD}/../../initrd
		make -j $(nproc)
		make install || exit
	cd ..
}

build_busybox () {
	# Building busybox
	wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
	tar -xf busybox-${BUSYBOX_VERSION}.tar.bz2
	cd busybox-${BUSYBOX_VERSION}
		make defconfig
		sed 's/^.*CONFIG_STATIC[^_].*$/CONFIG_STATIC=y/g' -i .config
		make -j $(nproc) busybox || exit
	cd ..
}

build_bash () {
	# Building bash
	wget https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz
	tar -xzf bash-${BASH_VERSION}.tar.gz
	cd bash-${BASH_VERSION}
		./configure --enable-static-link
		make -j $(nproc)
	cd ..
}

build_nano () {
	# Building nano
	wget https://nano-editor.org/dist/v7/nano-${NANO_VERSION}.tar.xz
	tar -xf nano-${NANO_VERSION}.tar.xz
	cd nano-${NANO_VERSION}
		./configure
		make -j $(nproc)
	cd ..
}

build_openssl () {
	wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
	tar -xzf openssl-${OPENSSL_VERSION}.tar.gz
	cd openssl-${OPENSSL_VERSION}
		./config -static
		make -j $(nproc)
	cd ..
}

fill_sbin_folder () {
  while read p; do
    find . -name "${p}" -type f -exec cp {} ../../../initrd/sbin/. \;
  done <../../../openrc/openrc_sbin_files.txt
}

fill_lib_bin_folder () {
  while read p; do
    find . -name "${p}" -type f -exec cp {} ../../../initrd/lib/rc/bin/. \;
  done <../../../openrc/openrc_lib_bin_files.txt
}

fill_lib_sbin_folder () {
  while read p; do
    find . -name "${p}" -type f -exec cp {} ../../../initrd/lib/rc/sbin/. \;
  done <../../../openrc/openrc_lib_sbin_files.txt
}

fill_lib_sh_folder () {
  while read p; do
    find . -name "${p}" -type f -exec cp {} ../../../initrd/lib/rc/sh/. \;
  done <../../../openrc/openrc_lib_sh_files.txt
}

build_openrc () {
	wget -O openrc-${OPENRC_VERSION}.tar.gz https://github.com/OpenRC/openrc/archive/refs/tags/${OPENRC_VERSION}.tar.gz
	tar -xzf openrc-${OPENRC_VERSION}.tar.gz
	cd openrc-${OPENRC_VERSION}
		meson setup buildir
		meson compile -C buildir
		cd buildir
			fill_lib_sh_folder
			fill_lib_sbin_folder
			fill_lib_bin_folder
			fill_sbin_folder
		cd ..
	cd ..
}

configure_network () {
	mkdir network
	cd network
		echo -e "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp" > interfaces
		mkdir ifup.d if-pre-up.d if-down.d if-post-down.d
	cd ..
}

create_initrd () {
	cd initrd
		
		# Configure bin folder
		cd bin
			# Copy busybox and create symlink for all the tool
			cp ../../src/bash-$BASH_VERSION/bash ./
			cp ../../src/busybox-$BUSYBOX_VERSION/busybox ./
			for prog in $(./busybox --list); do
				ln -s /bin/busybox ./$prog
			done

			# Copy nano
			cp ../../src/nano-${NANO_VERSION}/src/nano ./

			# Copy openssl
			cp ../../src/openssl-${OPENSSL_VERSION}/apps/openssl ./
		cd ..

		# Configure etc folder
		cd etc
			# passwd and shadow file
			echo 'root:x:0:0:root:/root:/bin/bash' > passwd
			echo 'root:$1$D5cv4HSB$f6ORrG9mIq5i1UeHOj72k/:19697:0:99999:7:::' > shadow

			# network interfaces
			configure_network
		cd ..

		# Construct the default init file
		# This is the part that should be replaced by systemd
		# Or OpenRC
		echo '#!/bin/bash' > init
		echo '' >> init
		echo '# Mount all required filesystem'
		echo 'mount -t proc proc /proc' >> init
		echo 'mount -t sysfs sysfs /sys' >> init
		echo 'mount -t devtmpfs udev /dev' >> init
		echo '' >> init
		echo '# Init all /dev devices' >> init
		echo '/bin/mdev -s' >> init 
		echo '' >> init
		echo '# Launching the busybox init' >> init
		echo 'clear' >> init
		echo '/bin/init' >> init
		chmod +x init

		# Make the initrd
		find . | cpio -o -H newc > ../initrd.img
	
	cd ..
}

init_build
cd src/
build_linux_kernel
build_glibc
build_busybox
build_bash
build_nano
build_openssl
#build_openrc
cd ../
create_initrd

