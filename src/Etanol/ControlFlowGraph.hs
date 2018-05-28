{-# LANGUAGE DuplicateRecordFields #-}

module Etanol.ControlFlowGraph
        (
                generateControlFlowGraph,
                CFG(..), dummyStart, dummyEnd,
                NodeData(..), EdgeData(..), theStart,
                theEnd, visualize, visualizeWrite, visualizeWriteAndDotifyForLinux
        ) where

-- TODO: Add the names of all the imported fields/functions in the imports below, by examining what is used in the code.

import Data.Word (Word8, Word16, Word32)
import ByteCodeParser.BasicTypes (
                CodeAtom, MethodInfo)
import ByteCodeParser.Reader    -- same in this case
import ByteCodeParser.Instructions
import Data.Graph.Inductive.Graph
import Data.Graph.Inductive.PatriciaTree -- see docs for `fgl` library for what these import

import System.Process (system)

import Data.Graph.Inductive.Dot (showDot, fglToDot)

import Control.Monad



data NodeData = NodeData {
                nodecode     :: CodeAtom -- from BasicTypes
        } deriving (Show, Eq, Ord)

data EdgeData = EdgeData deriving (Show, Eq, Ord)

type CFG = Gr NodeData EdgeData

dummyStart, dummyEnd :: LNode NodeData 
dummyStart = newNode (-1) (-1, [])
dummyEnd   = newNode (-2) (-2, [])

theStart, theEnd :: Int
theStart   = -1
theEnd     = -2

newNode :: Int -> CodeAtom -> LNode NodeData
newNode pos label = (pos, NodeData label)


-- one offs the code to attach to each codeatom the address of the next bytecode, so that it may be
-- used in getEdges , see generateControlFlowGraph
oneOff :: [CodeAtom] -> [(CodeAtom, Int)]
oneOff xs = zip xs $ tail (map (fromIntegral . fst) xs) ++ [theEnd]
                                                

generateControlFlowGraph :: [CodeAtom] -> CFG
generateControlFlowGraph code = let     g1 = mkGraph (map (\ca@(pos, subcode) -> newNode (fromIntegral pos) ca) code) []
                                        g1'= insNodes [dummyStart, dummyEnd] g1 
                                        g2 = insEdges (concatMap (uncurry getEdges) (oneOff code)) g1'
                                        g2'= insEdge (theStart, fst (code !! 0), EdgeData) g2
                                in      g2'
                                        


-- TODO: Cleanup these functions as most of their uses are from lists, so they can be written more succintly, see 'getEdges'
convert2 :: Word8 -> Word8 -> Int
convert4 :: Word8 -> Word8 -> Word8 -> Word8 -> Int
convert2 x y = let      [x', y'] = map fromIntegral [x, y] :: [Int]
                        p = x' * 2^8 + y'
                in if p > 2^15 then p - 2^16 else p

convert4 x y z w =      let     [x', y', z', w'] = map fromIntegral [x, y, z, w] :: [Int]
                                p = x' * 2^24 + y' * 2^16 + z' * 2^8 + w'
                        in      if p > 2^31 then p - 2^31 else p


-- [x1, x2, ... ] -> [[x1, .. xn], [xn + 1, .. x2n] .. ]
takeByGroups :: [a] -> Int -> [[a]]
takeByGroups [] _ = []
takeByGroups xs n = (take n xs) : takeByGroups (drop n xs) n 

-- Pickout which's elements from xs
pickOut :: [Int] -> [a] -> [a]
pickOut which xs = map (\f -> f xs) $ map (\x -> (\ls -> ls !! x)) $ takeWhile (< length xs) which

getEdges :: CodeAtom -> Int -> [LEdge EdgeData]
-- getEdges = undefined
getEdges (pos, (opcode : rest)) next 
        | opcode == opGoto =            let goTo = convert2 (rest!!0) (rest!!1)
                                        in  if goTo < 0 then [(pos, next, EdgeData)] else [(pos, pos + goTo, EdgeData)]
        | opcode == opGotoW =           let goTo = convert4 (rest!!0) (rest!!1) (rest!!2) (rest!!3)
                                        in if goTo < 0 then [(pos, next, EdgeData)] else [(pos, pos + goTo, EdgeData)]
        | opcode `elem` opIfs =         let goTo = convert2 (rest!!0) (rest!!1)
                                        in [    (pos, pos + goTo, EdgeData),
                                                (pos, next, EdgeData) ]
        | opcode `elem` opReturns =     [ (pos, theEnd, EdgeData) ]
        
        | opcode == opLookupSwitch =    let goTos = pickOut (0:[3,5..]) $ map (\[x, y, z, w] -> convert4 x y z w) $ takeByGroups rest 4           
                                                                                                                        -- to see why these are picked
                                        in map (\x -> (pos, pos + x, EdgeData)) goTos                                   -- see the code for the parsing
                                                                                                                        -- of these instructions in
                                                                                                                        -- Instructions.hs.
        | opcode == opTableSwitch =     let goTos = pickOut (0:[3..]) $ map (\[x, y, z, w] -> convert4 x y z w) $ takeByGroups rest 4              
                                        in map (\x -> (pos, pos + x, EdgeData)) goTos        

        | otherwise =                   [(pos, next, EdgeData)]


visualize :: CFG -> String
visualize cfg = showDot $ fglToDot cfg

visualizeWrite :: CFG -> FilePath -> IO ()
visualizeWrite cfg file = writeFile file $ visualize cfg

fileButSuffix :: FilePath -> String
fileButSuffix = reverse . tail . dropWhile (/= '.') . reverse

visualizeWriteAndDotifyForLinux :: CFG -> FilePath -> IO ()
visualizeWriteAndDotifyForLinux cfg file = do
                                                visualizeWrite cfg file
                                                x <- system $ "dot -Tpng -o" ++ fileButSuffix file ++ ".png " ++ file
                                                return ()
