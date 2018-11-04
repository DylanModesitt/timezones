import std / [times, unittest, options]
import .. / timezones
import .. / timezones / private / tzversion

let sweden = tz"Europe/Stockholm"

const f = "yyyy-MM-dd HH:mm zzz"

test "dst edge cases":
    # In case of an impossible time, the time is moved to after the impossible time period
    check initDateTime(26, mMar, 2017, 02, 30, 00, sweden).format(f) == "2017-03-26 03:30 +02:00"
    # In case of an ambiguous time, the earlier time is choosen
    check initDateTime(29, mOct, 2017, 02, 00, 00, sweden).format(f) == "2017-10-29 02:00 +02:00"
    # These are just dates on either side of the dst switch
    check initDateTime(29, mOct, 2017, 01, 00, 00, sweden).format(f) == "2017-10-29 01:00 +02:00"
    check initDateTime(29, mOct, 2017, 01, 00, 00, sweden).isDst
    check initDateTime(29, mOct, 2017, 03, 01, 00, sweden).format(f) == "2017-10-29 03:01 +01:00"
    check (not initDateTime(29, mOct, 2017, 03, 01, 00, sweden).isDst)
    
    check initDateTime(21, mOct, 2017, 01, 00, 00).format(f) == "2017-10-21 01:00 +02:00"

test "from utc":
    var local = fromUnix(1469275200).inZone(sweden)
    var utc = fromUnix(1469275200).utc
    let claimedOffset = local.utcOffset
    local.utcOffset = 0
    check claimedOffset == utc.toTime.toUnix - local.toTime.toUnix

test "staticTz":
    check staticTz(hours = 2).name == "-02:00"
    check staticTz(hours = 2, minutes = 1).name == "-02:01"
    check staticTz(hours = 2, minutes = 1, seconds = 13).name == "-02:01:13"
    check staticTz(hours = -1, minutes = -2, seconds = -3).name == "+01:02:03"
    check staticTz(hours = -1, minutes = 1).name == "+00:59"

    block:
        let tz = staticTz(seconds = 1)
        let dt = initDateTime(1, mJan, 2000, 00, 00, 00, tz)
        check dt.utcOffset == 1
    
    block:
        let tz = staticTz(hours = -2, minutes = -30)
        let dt = initDateTime(1, mJan, 2000, 12, 0, 0, tz)
        doAssert $dt == "2000-01-01T12:00:00+02:30"

# Does not yet work due to overflow/underflows bugs in the JS backend
# for int64. See #6752.
when not defined(js):
    test "large/small dates":
        let korea = tz"Asia/Seoul"
        let small = initDateTime(1, mJan, 0001, 00, 00, 00, korea)
        check small.utcOffset == -30472
        let large = initDateTIme(1, mJan, 2100, 00, 00, 00, korea)
        check large.utcOffset == -32400

test "validation":
    let str = "Invalid string"
    expect ValueError, (discard tz(str))
    doAssert location(str).isNone
    doAssert countries(str).len == 0
    expect ValueError, (discard tz(str))
    discard tzNames("YX") # Should not raise exception

test "location":
    check $((location"Europe/Stockholm").get) == "59° 20′ 0″ N 18° 3′ 0″ E"

test "Etc/UTC":
    check (location"Etc/UTC").isNone
    check tz"Etc/UTC" == utc()
    let dt = initDateTime(1, mJan, 1970, 00, 00, 00, utc())
    check $dt == $(dt.inZone(tz"Etc/UTC"))
    check (countries"Etc/UTC").len == 0

test "Dynamic tz data loading":
    const jsonContent = staticRead("../" & Version & ".json")
    let tzdata = parseJsonTimezones(jsonContent)
    check tzdata.tzNames("SE") == @["Europe/Stockholm"]
    check tzdata.version == Version

    # We use `timezonesPath` so we don't need to resolve the path ourself
    when defined(timezonesPath) and not defined(js):
        const timezonesPath {.strdefine.} = ""
        block:
            let tzdata = loadJsonTimezones(timezonesPath)
            check tzdata.tzNames("SE") == @["Europe/Stockholm"]
            check tzdata.version == Version