#Requires AutoHotkey v2.0

/**
 * @description Concatenate two arrays
 * @param {(Array)} arr1
 * @param {(Array)} arr2
 * @returns {(Array)} - the concatenated NEW array
 */
ArrConcat(arr1, arr2) {
    ret := arr1.Clone()
    for item in arr2 {
        ret.Push(item)
    }
    return ret
}

/**
 * @description Get an iterator from any iterable-like (maps, arrays, objects with __Enum etc.)
 * @param {(Object)} iterable - the iterable to get an iterator from
 * @param {(Integer)} arity - the arity of the iterator
 * @returns {(Function)} - the iterator function
 */
Iter(iterable, arity:=1) {
    return HasMethod(iterable, "__Enum") ? iterable.__Enum(arity) : iterable
}

/**
 * @description Get an iterator for the values of a map (or map-like)
 * @param {(Map)} iterable - the map to get an iterator for
 * @param {(FuncObj)} func - the function to apply to each item
 *   
 *         func(item) => Any
 * 
 * @returns {(FuncObj)} - the iterator function
 * 
 *         it(&item) => Boolean
 */
IterMap(iterable, func) {
    it := Iter(iterable)
    return (&item) => (
        res := it(&item),
        res and (item := func(item)),  ; Apply func to item, not res
        res
    )
}

/**
 * @description Flatten an iterable using a function (only 1 level)
 * @param {(Iterable)} iterable - the iterable to flatten
 * @param {(FuncObj)} func - the function to apply to each item. Should return an array of items
 *   
 *         func(item) => Array
 *  
 * @returns {(Array)} - a new 1-dimensional array with the items returned by the function
 */
ArrFlatMap(iterable, func) {
    ret := []

    for item in iterable {
        ret.Push(func(item)*)
    }
    return ret
}

/**
 * @description Join the items of an iterable into a string using a separator
 * @param {(Iterable)} iterable - the iterable to join
 * @param {(String)} separator - the separator to use
 * @returns {(String)} - the joined string
 */
IterJoin(iterable, separator) {
    it := Iter(iterable)

    ; Get the first item to initialize the loop
    if (!it(&item))
        return ""

    ret := "" item
    for item in it {
        ret .= separator item
    }
    return ret
}

/**
 * @description Get an iterator for the keys of a map (or map-like)
 * @param {(Map)} iterable - the map to get an iterator for
 * @returns {(FuncObj)} - the iterator function
 * 
 *         it(&key) => Boolean
 */
IterKeys(iterable) {
    it := Iter(iterable, 2)
    return (&key) => it(&key)
}

/**
 * @description Get an iterator for an array (or array-like, with known length) in reversed order
 * @param {(Array)} arr - the array to get an iterator for
 * @returns {(FuncObj)} - the iterator function
 * 
 *         it(&val) => Boolean
 */
ArrReversedIter(arr) {
    i := arr.Length
    return (&val) => (
        i > 0 ? (val := arr[i--], true): false
    )
}


ArrSort(arr, comparator := (a, b) => a - b) {
    static qsort(arr, l, r, comp) {
        if (l >= r)
            return

        pivot := arr[r]
        i := l
        j := r - 1
        while (i < j) {
            while (i < r and comp(arr[i], pivot) <= 0)
                i++
            while (j > l and comp(arr[j], pivot) >= 0)
                j--

            if (i >= j)
                break

            t := arr[i]
            arr[i] := arr[j]
            arr[j] := t
        }
        if (comp(arr[i], pivot) > 0) {
            arr[r] := arr[i]
            arr[i] := pivot
        }

        qsort(arr, l, i - 1, comp)
        qsort(arr, i + 1, r, comp)
    }
    qsort(arr, 1, arr.Length, comparator)
    return arr
}