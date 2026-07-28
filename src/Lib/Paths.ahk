#Requires AutoHotkey v2.0

/**
 * @description Repo-relative path resolution.
 * A_ScriptDir is useless here: two entry points exist (src/Main.ahk, tests/Main.ahk) and they sit
 * at different depths, so anything anchored on it resolves differently per entry. A_LineFile is
 * anchored on THIS file instead, so the layout depth is encoded in exactly one place.
 */
class Paths {
    /**
     * @description Repo root. A_LineFile = <root>\src\Lib\Paths.ahk -> strip 3 trailing segments.
     * Move this file and the strip count moves with it.
     * @returns {(String)} full path, no trailing backslash
     */
    static Root => RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+\\[^\\]+$")

    /**
     * @description Join a repo-relative path onto the root.
     * @param {(String)} relative e.g. "VirtualDesktopAccessor.dll"
     * @returns {(String)} full path
     */
    static FromRoot(relative) => Paths.Root . "\" . relative
}
