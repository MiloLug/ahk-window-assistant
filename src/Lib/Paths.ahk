#Requires AutoHotkey v2.0

/**
 * @description Useful path operations and constants
 */
class Paths {
    /**
     * @description Repo root
     */
    static Root := RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+\\[^\\]+$")
    ; A_LineFile = <root>\src\Lib\Paths.ahk -> strip trailing segments
    ; A_ScriptDir is useless, since if there are multiple entry points, they sit at different paths
    ; A_LineFile is always THIS file

    /**
     * @description Join a repo-relative path onto the root
     * @param {(String)} relative e.g. "some\path" -> "<repo root path>\some\path"
     * @returns {(String)} full path
     */
    static FromRoot(relative) => Paths.Root . "\" . Trim(relative, "\")
}
