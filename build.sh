#!/bin/bash
CRTDIR=$(pwd)
base=$1
profile=$2
ui=$3
tag=$4
tagm=$5
glversion=$6
glversiontype=$7
echo $base
if [ ! -e "$base" ]; then
    echo "Please enter base folder"
    exit 1
else
    if [ ! -d $base ]; then 
        echo "Openwrt base folder not exist"
        exit 1
    fi
fi

if [ ! -n "$profile" ]; then
    profile=target_wlan_ap-gl-ax1800
fi

if [ ! -n "$ui" ]; then
    ui=true
fi

if [ ! -n "$tag" ]; then
    tag=main
fi

if [ ! -n "$tagm" ]; then
    tagm=main
fi

if [[ $ui == true ]]; then
    git clone -b $tagm https://github.com/gl-inet/glinet4.x.git ~/glinet
    # add custom
    cp -r glinet4.x/*  ~/glinet/
    # add custom
fi

echo "Start..."

#clone source tree 
git clone -b $tag https://github.com/papagaye744/gl-infra-builder.git $base/gl-infra-builder
# add custom start
cp -r gl-infra-builder/*  $base/gl-infra-builder/
rm -f $base/gl-infra-builder/patches-mt798x-7.6.6.1/3003-target-mediatek-mtk-eth-poll-gpy211-link-state.patch
# add fullcorenat
# git clone -b master https://github.com/LGA1150/openwrt-fullconenat.git custom/openwrt-fullconenat
# git clone -b master https://github.com/peter-tank/luci-app-fullconenat.git custom/luci-app-fullconenat
# add passwall
git clone --depth 1 -b main https://github.com/White12352/openwrt-passwall-packages custom/passwall
git clone --depth 1 -b luci-smartdns-dev https://github.com/White12352/openwrt-passwall custom/luci-app-passwall
# add custom ended
cp -r custom/  $base/gl-infra-builder/feeds/custom/
cp -r *.yml $base/gl-infra-builder/profiles
cd $base/gl-infra-builder


function build_firmware(){
    cd ~/openwrt
    ls -la
    need_gl_ui=$1
    ui_path=$2
    # setup version
    echo "$glversion" > package/base-files/files/etc/glversion
    # echo `date '+%Y-%m-%d %H:%M:%S'` > package/base-files/files/etc/version.date
    echo "$glversiontype" > package/base-files/files/etc/version.type
    
    # fix helloword build error
    rm -rf feeds/packages/lang/golang
    #rm -rf feeds/packages/lang/rust
    #svn co https://github.com/openwrt/packages/branches/openwrt-23.05/lang/golang feeds/packages/lang/golang
    git clone --depth 1 -b openwrt-23.05 https://github.com/openwrt/packages custom/t
    cp -rf custom/t/lang/golang feeds/packages/lang/golang
    #cp -rf custom/t/lang/rust feeds/packages/lang/rust
    rm -rf custom/t
    rm -rf feeds/gl_feed_common/golang
    #rm -rf feeds/gl_feed_common/rust
    #svn co https://github.com/openwrt/packages/branches/openwrt-23.05/lang/golang feeds/gl_feed_common/golang
    cp -rf feeds/packages/lang/golang feeds/gl_feed_common/golang
    #cp -rf feeds/packages/lang/rust feeds/gl_feed_common/rust
    
    # update tailscale
    rm -rf feeds/gl_feed_common/tailscale
    cp -rf $CRTDIR/src/tailscale feeds/gl_feed_common/
    
    # fix upnp https://forum.gl-inet.cn/forum.php?mod=viewthread&tid=3240&highlight=upnp
    rm -rf feeds/packages/net/miniupnpd
    git clone --depth 1 -b openwrt-23.05 https://github.com/immortalwrt/packages custom/t2
    #svn co https://github.com/immortalwrt/packages/branches/openwrt-18.06/net/miniupnpd feeds/packages/net/miniupnpd
    cp -rf custom/t2/net/miniupnpd feeds/packages/net/miniupnpd
    rm -rf custom/t2

    # fix compile kmod-inet-diag
    awk '/^\$\(eval \$\(call KernelPackage,netlink-diag\)\)/{print "$(eval $(call KernelPackage,netlink-diag))"; print ""; print ""; print "define KernelPackage/inet-diag"; print "  SUBMENU:=$(NETWORK_SUPPORT_MENU)"; print "  TITLE:=INET diag support for ss utility"; print "  KCONFIG:= \\"; print "\tCONFIG_INET_DIAG \\"; print "\tCONFIG_INET_TCP_DIAG \\"; print "\tCONFIG_INET_UDP_DIAG \\"; print "\tCONFIG_INET_RAW_DIAG \\"; print "\tCONFIG_INET_DIAG_DESTROY=n"; print "  FILES:= \\"; print "\t$(LINUX_DIR)/net/ipv4/inet_diag.ko \\"; print "\t$(LINUX_DIR)/net/ipv4/tcp_diag.ko \\"; print "\t$(LINUX_DIR)/net/ipv4/udp_diag.ko \\"; print "\t$(LINUX_DIR)/net/ipv4/raw_diag.ko"; print "  AUTOLOAD:=$(call AutoLoad,31,inet_diag tcp_diag udp_diag raw_diag)"; print "endef"; print ""; print "define KernelPackage/inet-diag/description"; print "Support for INET (TCP, DCCP, etc) socket monitoring interface used by"; print "native Linux tools such as ss."; print "endef"; print ""; print "$(eval $(call KernelPackage,inet-diag))"; next}1' package/kernel/linux/modules/netsupport.mk > temp_file && mv -f temp_file package/kernel/linux/modules/netsupport.mk

    # update smartdns
    #rm -rf feeds/luci/applications/luci-app-smartdns
    #rm -rf feeds/packages/net/smartdns
    #svn co https://github.com/kenzok8/openwrt-packages/trunk/luci-app-smartdns feeds/luci/applications/luci-app-smartdns
    #svn co https://github.com/kenzok8/openwrt-packages/trunk/smartdns feeds/packages/net/smartdns
    
    # add fullcorenat patch
    # mkdir package/network/config/firewall/patches
    # cp $CRTDIR/fullconenat.patch package/network/config/firewall/patches/fullconenat.patch
    
    #install feed 
    ./scripts/feeds update -a && ./scripts/feeds install -a && make defconfig
    #build 
    if [[ $need_gl_ui == true  ]]; then 
        make -j$(expr $(nproc) + 1) GL_PKGDIR=~/glinet/$ui_path/
        if [ $? -ne 0 ]; then
            make GL_PKGDIR=~/glinet/$ui_path/ V=s
        fi
    else
        make -j$(expr $(nproc) + 1) V=s
        if [ $? -ne 0 ]; then
            make V=s
        fi
    fi
    return
}

function copy_file(){
    path=$1
    mkdir ~/firmware
    mkdir ~/packages
    cd $path
    rm -rf packages
    cp -rf ./* ~/firmware
    cp -rf ~/openwrt/bin/packages/* ~/packages
    return
}

case $profile in 
    target_wlan_ap-gl-ax1800|\
    target_wlan_ap-gl-axt1800|\
    target_wlan_ap-gl-ax1800-5-4|\
    target_wlan_ap-gl-axt1800-5-4)
        if [[ $profile == *5-4* ]]; then
            python3 setup.py -c configs/config-wlan-ap-5.4.yml
        else
            python3 setup.py -c configs/config-wlan-ap.yml
        fi
        ln -s $base/gl-infra-builder/wlan-ap/openwrt ~/openwrt && cd ~/openwrt
        if [[ $ui == true  ]]; then 
            if [[ $profile == *ax1800* ]]; then
                cp ~/glinet/pkg_config/gl_pkg_config_ax1800.mk  ~/glinet/ipq60xx/gl_pkg_config.mk
                cp ~/glinet/pkg_config/glinet_depends_ax1800.yml  ./profiles/glinet_depends.yml
            else
                cp ~/glinet/pkg_config/gl_pkg_config_axt1800.mk  ~/glinet/ipq60xx/gl_pkg_config.mk
                cp ~/glinet/pkg_config/glinet_depends_axt1800.yml  ./profiles/glinet_depends.yml
            fi
            ./scripts/gen_config.py glinet_depends custom
        else
            ./scripts/gen_config.py $profile openwrt_common glinet_nas luci custom
        fi
        build_firmware $ui ipq60xx && copy_file ~/openwrt/bin/targets/*/*
    ;;
    target_mt7981_gl-mt2500|\
    target_mt7981_gl-mt3000|\
    target_mt7981_qh-360t7|\
    target_mt7981_gl-x3000|\
    target_mt7981_gl-xe3000)
        python3 setup.py -c configs/config-mt798x-7.6.6.1.yml
        ln -s $base/gl-infra-builder/mt7981 ~/openwrt && cd ~/openwrt
        ./scripts/gen_config.py $profile luci
        if [[ $ui == true  ]]; then
            if [[ $profile == *360t7* ]]; then
                cp ~/glinet/pkg_config/gl_pkg_config_360t7.mk  ~/glinet/mt7981/gl_pkg_config.mk
                # cp ~/glinet/pkg_config/glinet_depends_360t7.yml  ./profiles/glinet_depends.yml
                # ./scripts/gen_config.py glinet_depends custom
                ./scripts/gen_config.py keepfeeds $profile glinet_depends custom
            elif [[ $profile == *mt3000* ]]; then
                cp ~/glinet/pkg_config/gl_pkg_config_mt3000.mk  ~/glinet/mt7981/gl_pkg_config.mk
                cp ~/glinet/pkg_config/glinet_depends_mt3000.yml  ./profiles/glinet_depends.yml
                ./scripts/gen_config.py glinet_depends custom
            elif [[ $profile == *mt2500* ]]; then
                cp ~/glinet/pkg_config/gl_pkg_config_mt2500.mk  ~/glinet/mt7981/gl_pkg_config.mk
                cp ~/glinet/pkg_config/glinet_depends_mt2500.yml  ./profiles/glinet_depends.yml
                ./scripts/gen_config.py glinet_depends custom
            else
                ./scripts/gen_config.py $profile glinet_nas custom
            fi
        else
            ./scripts/gen_config.py $profile glinet_nas custom
        fi
        build_firmware $ui mt7981 && copy_file ~/openwrt/bin/targets/*/*
    ;;
    target_siflower_gl-sf1200|\
    target_siflower_gl-sft1200)
        python3 setup.py -c configs/config-siflower-18.x.yml
        ln -s $base/gl-infra-builder/openwrt-18.06/siflower/openwrt-18.06 ~/openwrt && cd ~/openwrt
        ./scripts/gen_config.py $profile glinet_nas custom
        build_firmware && copy_file ~/openwrt/bin/targets/*
    ;;
    target_ath79_gl-s200|\
    target_ipq40xx_gl-a1300)
        ui_path=
        python3 setup.py -c configs/config-21.02.2.yml
        ln -s $base/gl-infra-builder/openwrt-21.02/openwrt-21.02.2 ~/openwrt && cd ~/openwrt
        if [[ $ui == true  ]]; then
            if [[ $profile == *s200* ]]; then
                cp -rf ~/glinet/pkg_config/gl_pkg_config_ath79_s200.mk ~/glinet/ath79/gl_pkg_config.mk
                cp -rf ~/glinet/pkg_config/gl_pkg_config_ath79_s200.yml ./profiles/
                ./scripts/gen_config.py $profile gl_pkg_config_ath79_s200 custom
                ui_path=ath79
            elif [[ $profile == *a1300* ]]; then
                cp ~/glinet/pkg_config/gl_pkg_config_a1300.mk  ~/glinet/ipq40xx/gl_pkg_config.mk
                cp ~/glinet/pkg_config/glinet_depends_a1300.yml  ./profiles/glinet_depends.yml
                ./scripts/gen_config.py glinet_depends custom
                ui_path=ipq40xx
            else
                ./scripts/gen_config.py $profile openwrt_common glinet_nas luci custom
            fi
        else
            ./scripts/gen_config.py $profile openwrt_common glinet_nas luci custom
        fi
        build_firmware $ui $ui_path && copy_file ~/openwrt/bin/targets/*/*
    ;;
    target_ath79_gl-ar300m-nor|\
    target_ath79_gl-ar300m-nand|\
    target_ath79_gl-x300b-nor|\
    target_ath79_gl-x300b-nor-nand|\
    target_ramips_gl-mt1300)
        python3 setup.py -c configs/config-22.03.4.yml
        ln -s $base/gl-infra-builder/openwrt-22.03/openwrt-22.03.4 ~/openwrt && cd ~/openwrt
        ./scripts/gen_config.py $profile luci custom
        build_firmware && copy_file ~/openwrt/bin/targets/*/*
    ;;
esac

