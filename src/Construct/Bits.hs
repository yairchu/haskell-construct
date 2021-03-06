{-# LANGUAGE GADTs #-}

-- | This module exports the primitives and combinators for constructing formats with sub- or cross-byte
-- components. See @test/MBR.hs@ for an example of its use.

module Construct.Bits
  (Bits, bit,
   -- * The combinators for converting between 'Bits' and 'ByteString' input streams
   bigEndianBitsOf, bigEndianBytesOf, littleEndianBitsOf, littleEndianBytesOf) where

import Data.Bits (clearBit, setBit, testBit)
import Data.Bool (bool)
import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import qualified Data.List as List
import Data.Word (Word8)

import Construct
import Construct.Classes
import Construct.Internal

-- | The list of bits
type Bits = [Bool]

bit :: (Applicative n, InputParsing m, ParserInput m ~ Bits) => Format m n Bits Bool
bigEndianBitsOf :: (InputParsing (m Bits), InputParsing (m ByteString), InputMappableParsing m, Functor n,
                    ParserInput (m Bits) ~ Bits, ParserInput (m ByteString) ~ ByteString) =>
                   Format (m ByteString) n ByteString a -> Format (m Bits) n Bits a
bigEndianBytesOf :: (InputParsing (m Bits), InputParsing (m ByteString), InputMappableParsing m, Functor n,
                     ParserInput (m Bits) ~ Bits, ParserInput (m ByteString) ~ ByteString) =>
                    Format (m Bits) n Bits a -> Format (m ByteString) n ByteString a
littleEndianBitsOf :: (InputParsing (m Bits), InputParsing (m ByteString), InputMappableParsing m, Functor n,
                       ParserInput (m Bits) ~ Bits, ParserInput (m ByteString) ~ ByteString) =>
                      Format (m ByteString) n ByteString a -> Format (m Bits) n Bits a
littleEndianBytesOf :: (InputParsing (m Bits), InputParsing (m ByteString), InputMappableParsing m, Functor n,
                        ParserInput (m Bits) ~ Bits, ParserInput (m ByteString) ~ ByteString) =>
                       Format (m Bits) n Bits a -> Format (m ByteString) n ByteString a

-- | The primitive format of a single bit
bit = Format{
   parse = head <$> anyToken,
   serialize = pure . (:[])}

bigEndianBitsOf = mapMaybeSerialized (Just . enumerateFromMostSignificant) collectFromMostSignificant
bigEndianBytesOf = mapMaybeSerialized collectFromMostSignificant (Just . enumerateFromMostSignificant)
littleEndianBitsOf = mapMaybeSerialized (Just . enumerateFromLeastSignificant) collectFromLeastSignificant
littleEndianBytesOf = mapMaybeSerialized collectFromLeastSignificant (Just . enumerateFromLeastSignificant)

collectFromMostSignificant :: Bits -> Maybe ByteString
collectFromLeastSignificant :: Bits -> Maybe ByteString
enumerateFromMostSignificant :: ByteString -> Bits
enumerateFromLeastSignificant :: ByteString -> Bits

collectFromMostSignificant bits = (ByteString.pack . map toByte) <$> splitEach8 bits
   where toByte octet = List.foldl' setBit (0 :: Word8) (map snd $ filter fst $ zip octet [7,6..0])
collectFromLeastSignificant bits = (ByteString.pack . map toByte) <$> splitEach8 bits
   where toByte octet = List.foldl' setBit (0 :: Word8) (map snd $ filter fst $ zip octet [0..7])
enumerateFromMostSignificant = ByteString.foldr ((++) . enumerateByte) []
   where enumerateByte b = [testBit b i | i <- [7,6..0]]
enumerateFromLeastSignificant = ByteString.foldr ((++) . enumerateByte) []
   where enumerateByte b = [testBit b i | i <- [0..7]]

splitEach8 :: [a] -> Maybe [[a]]
splitEach8 [] = Just []
splitEach8 list
   | length first8 == 8 = (first8 :) <$> splitEach8 rest
   | otherwise = Nothing
   where (first8, rest) = splitAt 8 list
