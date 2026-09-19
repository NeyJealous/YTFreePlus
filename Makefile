DEBUG = 0
FINALPACKAGE = 1
ARCHS = arm64
TARGET := iphone:clang:16.5:13.0
PACKAGE_VERSION = 0.1.0

include $(THEOS)/makefiles/common.mk

before-all::
	@python3 scripts/sync_vot_config.py

TWEAK_NAME = YTFreePlus
YTFreePlus_FILES = YTFreePlus.x \
	VOT/VOTConfig.m \
	VOT/VOTSigner.m \
	VOT/VOTProto.m \
	VOT/VOTSession.m \
	VOT/VOTTranslation.m \
	VOT/VOTClient.m \
	VOT/VOTAudioPlayer.m \
	VOT/VOTManager.m
YTFreePlus_FRAMEWORKS = UIKit Foundation AVFoundation
YTFreePlus_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
YTFreePlus_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
