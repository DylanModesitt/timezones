import times
import strutils
import timezones/private/binformat

# xxx the silly default path is because it's relative to "binformat.nim"
const embedTzdb {.strdefine.} = "../../bundled_tzdb_file/2017c.bin"

proc initTimezone(offset: int): Timezone =

    proc zoneInfoFromTz(adjTime: Time): ZonedTime {.locks: 0.} =
        result.isDst = false
        result.utcOffset = offset
        result.adjTime = adjTime

    proc zoneInfoFromUtc(time: Time): ZonedTime {.locks: 0.}=
        result.isDst = false
        result.utcOffset = offset
        result.adjTime = time + initDuration(seconds = offset)

    result.name = ""
    result.zoneInfoFromTz = zoneInfoFromTz
    result.zoneInfoFromUtc = zoneInfoFromUtc

template binarySeach(transitions: seq[Transition],
                     field: untyped, t: Time): int =

    var lower = 0
    var upper = transitions.high
    while lower < upper:
        var mid = (lower + upper) div 2
        if transitions[mid].field >= t.toUnix:
            upper = mid - 1
        elif lower == mid:
            break
        else:
            lower = mid
    lower

proc initTimezone(tz: InternalTimezone): Timezone =
    # xxx it might be bad to keep the transitions in the closure,
    # since they're so many.
    # Probably better if the closure keeps a small reference to the index in the
    # shared db.
    proc zoneInfoFromTz(adjTime: Time): ZonedTime {.locks: 0.} =
        let index = tz.transitions.binarySeach(startAdj, adjTime)

        let transition = tz.transitions[index]

        if index < tz.transitions.high:
            let current = tz.transitions[index]
            let next = tz.transitions[index + 1]
            let offsetDiff = next.utcOffset - current.utcOffset
            # This means that we are in the invalid time between two transitions
            if adjTime.toUnix > next.startAdj - offsetDiff:
                result.isDst = next.isDst
                result.utcOffset = -next.utcOffset
                result.adjTime = adjTime +
                    initDuration(seconds = offsetDiff)
                return

        result.isDst = transition.isDst
        result.utcOffset = -transition.utcOffset
        result.adjTime = adjTime

        if index != 0:
            let prevTransition = tz.transitions[index - 1]
            let offsetDiff = transition.utcOffset - prevTransition.utcOffset
            let adjUnix = adjTime.toUnix

            if offsetDiff < 0:
                # Times in this interval are ambigues
                # Resolved by picking earlier transition
                if transition.startAdj <= adjUnix and
                        adjUnix < transition.startAdj - offsetDiff:
                    result.isDst = prevTransition.isDst
                    result.utcOffset = -prevTransition.utcOffset
                
    proc zoneInfoFromUtc(time: Time): ZonedTime {.locks: 0.} =
        let transition = tz.transitions[tz.transitions.binarySeach(startUtc, time)]
        result.isDst = transition.isDst
        result.utcOffset = -transition.utcOffset
        result.adjTime = time + initDuration(seconds = transition.utcOffset)

    result.name = tz.name
    result.zoneInfoFromTz = zoneInfoFromTz
    result.zoneInfoFromUtc = zoneInfoFromUtc

proc staticTz*(hours, minutes, seconds: int = 0): Timezone {.noSideEffect.} =
    ## Create a timezone using a static offset from UTC.
    runnableExamples:
        import times
        let tz = staticTz(hours = -2, minutes = -30)
        let dt = initDateTime(1, mJan, 2000, 12, 00, 00, tz)
        doAssert $dt == "2000-01-01T12:00:00+02:30"

    let offset = hours * 3600 + minutes * 60 + seconds
    result = initTimezone(offset)

const read = binformat.staticReadFromFile tzdbpath

# Future improvements:
#  - Put all transitions in an array[int, array[int, Transition]]
#  - Put names in a HashTable[string, int]
#  - In the timezone closure, only keep the tz index around.
#    Note that reading the transitions is gcsafe.

when read.status == rsSuccess:
    const staticDatabase = read.payload
elif read.status == rsFileDoesNotExist:
    {.fatal: "Failed to read tzdb file: '" &
        tzdbpath & "' does not exist.".}
elif read.status == rsIncorrectFormatVersion:
    {.fatal: "Found unexpected tzdb format version in '" &
        tzdbpath & "'.\n" &
        "Either the file is corrupt, " &
        "it's generated by an old version of fetchtzdb, " &
        "or it's not a tzdb file at all. " &
        "You need to regenerate the tzdb file.".}
else:
    {.fatal: "Unexpected failure".}

let timezoneDatabase = staticDatabase.finalize

proc resolveTimezone(name: string): tuple[exists: bool, candidate: string] =
    var bestCandidate: string
    var bestDistance = high(int)
    for tz in staticDatabase.timezones:
        if tz.name == name:
            return (true, "")
        else:
            let distance = editDistance(tz.name, name)
            if distance < bestDistance:
                bestCandidate = tz.name
                bestDistance = distance
    return (false, bestCandidate)

proc tzImpl(name: string): Timezone =
    # xxx make it a hashtable or something
    for tz in timezoneDatabase.timezones:
        if tz.name == name:
            result = initTimezone(tz)

proc tz*(name: string): Timezone {.inline.} =
    ## Create a timezone using a name from the IANA timezone database.
    runnableExamples:
        let sweden = tz"Europe/Stockholm"
        let dt = initDateTime(1, mJan, 1850, 00, 00, 00, sweden)
        doAssert $dt == "1850-01-01T00:00:00-01:12"

    result = tzImpl name

proc tz*(name: static[string]): Timezone {.inline.} =
    ## Create a timezone using a name from the IANA timezone database.
    ## Validates the timezone name during compile time.
    runnableExamples:
        let sweden = tz"Europe/Stockholm"
        let dt = initDateTime(1, mJan, 1850, 00, 00, 00, sweden)
        doAssert $dt == "1850-01-01T00:00:00-01:12"

    const resolved = name.resolveTimezone
    when not resolved.exists:
        {.fatal: "Timezone not found: '" & name &
            "'.\nDid you mean '" & resolved.candidate & "'?".}
    
    result = tzImpl name

const TzdbMetadata* = (
    year: staticDatabase.version.year,
    release: staticDatabase.version.release.char,
    version: $staticDatabase.version.year & staticDatabase.version.release,
    startYear: staticDatabase.startYear,
    endYear: staticDatabase.endYear
)
