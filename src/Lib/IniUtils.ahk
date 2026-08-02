#Requires AutoHotkey v2.0

/**
 * @description INI loader with env vars expansion.
 * E.g. you can use %ENV_VAR_NAME% (for ex %SystemRoot%) right in the INI
 */
class IniUtils {
    /**
     * @description Load an ini file into nested Maps
     * @param {(String)} path ini file path
     * @returns {(Map)} section name -> Map(key -> value) - case insensitive map (CaseSense = Off)
     */
    static Load(path) {
        if (!FileExist(path))
            throw Error("Ini file not found: " path)
        ini := Map()
        ini.CaseSense := "Off"
        for section in StrSplit(IniRead(path), "`n") {
            if (section = "")
                continue
            pairs := Map()
            pairs.CaseSense := "Off"
            for line in StrSplit(IniRead(path, section), "`n") {
                eq := InStr(line, "=")
                if (!eq)
                    continue
                pairs[Trim(SubStr(line, 1, eq - 1))] := IniUtils.ExpandVars(Trim(SubStr(line, eq + 1)))
            }
            ini[section] := pairs
        }
        return ini
    }

    /**
     * @description Replace each %NAME% in str with its environment variable.
     * Unset vars stay literal.
     * @param {(String)} str raw value
     * @returns {(String)} expanded value
     */
    static ExpandVars(str) {
        out := ""
        pos := 1
        while (found := RegExMatch(str, "%([^%]+)%", &m, pos)) {
            val := EnvGet(m[1])
            out .= SubStr(str, pos, found - pos) . (val != "" ? val : m[0])
            pos := found + StrLen(m[0])
        }
        return out . SubStr(str, pos)
    }
}
