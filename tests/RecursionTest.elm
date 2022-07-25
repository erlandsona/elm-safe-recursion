module RecursionTest exposing (suite)

import Dict exposing (Dict)
import Expect
import Fuzz
import Recursion exposing (..)
import Recursion.Traverse exposing (..)
import Test exposing (..)


slowSum : Int -> Float
slowSum =
    runRecursion
        (\i ->
            case i of
                0 ->
                    base 0.0

                _ ->
                    recurse (i - 1) |> andThen (\f -> base <| f + toFloat i)
        )


fastSum : Int -> Float
fastSum i_ =
    runRecursion
        (\( i, acc ) ->
            case i of
                0 ->
                    base acc

                _ ->
                    recurse ( i - 1, acc + toFloat i )
        )
        ( i_, 0.0 )


type Tree a
    = Leaf a
    | Node (Tree a) (Tree a)


{-| Makes a tree of 2^n nodes
-}
makeDeepTree : (Int -> a) -> Int -> Tree a
makeDeepTree f =
    runRecursion
        (\i ->
            case i of
                0 ->
                    base <| Leaf (f 0)

                _ ->
                    recurse (i - 1) |> andThen (\tree -> base (Node tree tree))
        )


{-| Makes a tree of n nodes
-}
makeDeepLeftTree : (Int -> a) -> Int -> Tree a
makeDeepLeftTree f =
    runRecursion
        (\i ->
            case i of
                0 ->
                    base <| Leaf (f 0)

                _ ->
                    recurse (i - 1) |> andThen (\tree -> base (Node tree (Leaf <| f i)))
        )


mapTree : (a -> b) -> Tree a -> Tree b
mapTree f =
    runRecursion
        (\tree ->
            case tree of
                Leaf a ->
                    base <| Leaf (f a)

                Node l r ->
                    recurse l
                        |> andThen
                            (\l_ ->
                                recurse r
                                    |> map (\r_ -> Node l_ r_)
                            )
        )


type RoseTree a
    = RoseLeaf a
    | RoseNode (List (RoseTree a))


mapRoseTree : (x -> y) -> RoseTree x -> RoseTree y
mapRoseTree f =
    runRecursion
        (\roseTree ->
            case roseTree of
                RoseLeaf a ->
                    base <| RoseLeaf (f a)

                RoseNode elems ->
                    traverseList recurse elems
                        |> andThen (\nodes -> base (RoseNode nodes))
        )



{-
   x = RoseNode [n1, n2, n3, n4]

   Loop n1 (\b1 -> Loop n2 (\b2 -> Loop n3 (\b3 -> Loop n4 (\b4 -> RoseNode [b1, b2, b3, b4]))))
-}


bigRoseTree : Int -> Int -> (Int -> x) -> RoseTree x
bigRoseTree depth breadth makeElem =
    case depth of
        0 ->
            List.range 0 breadth |> List.map (makeElem >> RoseLeaf) |> RoseNode

        _ ->
            bigRoseTree (depth - 1) breadth makeElem |> List.singleton |> RoseNode


safetyTests : Test
safetyTests =
    describe "Safety Tests"
        [ test "slowSum doesn't stack overflow" <|
            \_ ->
                slowSum 100000 |> Expect.within (Expect.Absolute 0) ((100000.0 * 100001.0) / 2.0)
        , test "fastSum doesn't stack overflow" <|
            \_ ->
                fastSum 100000 |> Expect.within (Expect.Absolute 0) ((100000.0 * 100001.0) / 2.0)
        , test "makeDeepLeftTree doesn't stack overflow" <|
            \_ ->
                let
                    _ =
                        makeDeepTree identity 1000
                in
                Expect.pass
        , test "mapTree doesn't stack overflow" <|
            \_ ->
                let
                    -- tree has 2^16 nodes
                    --tree =
                    --   makeDeepTree identity 1
                    tree =
                        Node (Leaf 0) (Leaf 1)

                    mapped =
                        mapTree (\x -> String.fromInt x) tree
                in
                Expect.pass
        , test "mapRoseTree doesn't stack overflow" <|
            \_ ->
                let
                    tree =
                        bigRoseTree 2 100000 identity

                    _ =
                        mapRoseTree String.fromInt tree
                in
                Expect.pass
        ]


mapRec : (a -> b) -> List a -> Rec (List a) (List b) (List b)
mapRec f list =
    case list of
        [] ->
            base []

        item :: rest ->
            recurse rest |> map (\items -> f item :: items)


functorLawTests : Test
functorLawTests =
    describe "Functor Laws"
        [ Test.fuzz (Fuzz.list Fuzz.int) "Functors preserve identity morphisms" <|
            \list ->
                let
                    rec =
                        mapRec (\x -> x + 1)
                in
                Expect.equalLists
                    (runRecursion (rec >> map identity) list)
                    (runRecursion (rec >> identity) list)
        , Test.fuzz (Fuzz.list Fuzz.int) "Functors preserve composition of morphisms" <|
            \list ->
                let
                    rec =
                        mapRec (\x -> x + 1)

                    f =
                        List.map (\x -> x // 3)

                    g =
                        List.map (\x -> x * 2)
                in
                Expect.equalLists
                    (runRecursion (rec >> map (f >> g)) list)
                    (runRecursion (rec >> (map f >> map g)) list)
        ]


monadLawTests : Test
monadLawTests =
    describe "Monad Laws"
        [ Test.fuzz (Fuzz.list Fuzz.int) "Left identity [ return a >>= h === h a ]" <|
            \list ->
                let
                    a =
                        [ 7 ]

                    h =
                        \items -> base <| items ++ [ 1 ]
                in
                Expect.equalLists
                    (runRecursion (\_ -> base a |> andThen h) list)
                    (runRecursion (\_ -> h a) list)
        , Test.fuzz (Fuzz.list Fuzz.int) "Right identity [ m >>= return === m ]" <|
            \list ->
                Expect.equalLists
                    (runRecursion (mapRec (\x -> x + 1) >> andThen base) list)
                    (runRecursion (mapRec (\x -> x + 1)) list)
        , Test.fuzz (Fuzz.list Fuzz.int) "Associativity [ (m >>= g) >>= h === m >>= (\\x -> g x >>= h) ]" <|
            -- TODO
            \_ -> Expect.pass
        ]


type DictTree a
    = DictLeaf a
    | DictNode (Dict String (DictTree a))


mapDictTree : (a -> b) -> DictTree a -> DictTree b
mapDictTree f =
    runRecursion
        (\tree ->
            case tree of
                DictLeaf a ->
                    base <| DictLeaf (f a)

                DictNode dict ->
                    dict |> traverseDict (\v -> recurse v) |> map DictNode
        )


traverseDictTest : Test
traverseDictTest =
    describe "traverseDict"
        [ test "traverseDict is correct" <|
            \_ ->
                let
                    input =
                        DictNode (Dict.fromList [ ( "a", DictLeaf 1 ), ( "b", DictLeaf 2 ) ])

                    expected =
                        DictNode (Dict.fromList [ ( "a", DictLeaf "1" ), ( "b", DictLeaf "2" ) ])
                in
                Expect.equal (mapDictTree String.fromInt input) expected
        ]


suite : Test
suite =
    describe "Recursion"
        [ safetyTests
        , functorLawTests
        , monadLawTests
        , traverseDictTest
        ]
