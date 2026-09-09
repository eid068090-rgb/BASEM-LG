package com.basem.devicefinder;

public final class DeviceMerger {
    private DeviceMerger() {}

    public static void mergeInto(Device old, Device newer) {
        if (Device.notBlank(newer.hostname)) old.hostname = newer.hostname;
        if (Device.notBlank(newer.ip)) old.ip = newer.ip;
        if (Device.notBlank(newer.mac)) old.mac = newer.mac;
        if (Device.notBlank(newer.model)) old.model = newer.model;
        if (Device.notBlank(newer.wirelessName)) old.wirelessName = newer.wirelessName;
        if (Device.notBlank(newer.firmware)) old.firmware = newer.firmware;
        if (Device.notBlank(newer.boardName)) old.boardName = newer.boardName;
        if (Device.notBlank(newer.firmwareType)) old.firmwareType = newer.firmwareType;
        if (Device.notBlank(newer.discoveryType)) old.discoveryType = newer.discoveryType;
        old.raw.putAll(newer.raw);
    }
}
