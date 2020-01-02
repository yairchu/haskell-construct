{-# LANGUAGE FlexibleInstances, StandaloneDeriving, TemplateHaskell, TypeApplications, TypeFamilies #-}

module Construct where

import qualified Control.Applicative as Applicative
import qualified Control.Monad.Fix as Monad.Fix
import Control.Applicative (Applicative, Alternative)
import Control.Monad.Fix (MonadFix)
import Data.Functor ((<$>), void)
import Data.Functor.Identity
import qualified Data.Functor.Const as Functor
import Data.Word (Word, Word8)
import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ASCII
import Data.Monoid.Factorial (FactorialMonoid)
import Data.Monoid.Cancellative (LeftReductiveMonoid)
import Text.Grampa (InputParsing(ParserInput, anyToken, getInput, string))
import Text.Parser.Combinators (count)
import qualified Data.Attoparsec.ByteString as Attoparsec
import qualified Text.ParserCombinators.Incremental as Incremental
import Text.ParserCombinators.Incremental.Symmetric (Symmetric)
import Data.Serialize (Serialize, bytesRead, get, put, runGet, runPut)

import qualified Rank2
import qualified Rank2.TH

import Prelude hiding ((*>), (<*))

data BitMap f = BitMap{
   width :: f Word8,
   height :: f Word8,
   pixels :: f [[Word8]]
   }

deriving instance Show (BitMap Identity)

$(Rank2.TH.deriveAll ''BitMap)

format :: Format (Incremental.Parser Symmetric ByteString) Identity ByteString (BitMap Identity)
format = literal (ASCII.pack "BMP") *> record
  BitMap{
        width= cereal @Word8,
        height= cereal @Word8,
        pixels= matrix 2 3 cereal
        }

data Format m n s a = Format {
   parse :: m a,
   serialize :: a -> n s
   }

(*>)    :: (Applicative m, Semigroup (n s)) => Format m n s () -> Format m n s a -> Format m n s a
(<*)    :: Applicative m => Format m n s a -> Format m n s () -> Format m n s a
(<|>)   :: (Alternative m, Alternative n) => Format m n s a -> Format m n s a -> Format m n s a
empty   :: (Alternative m, Alternative n) => Format m n s a
mfix    :: MonadFix m => (a -> Format m n s a) -> Format m n s a
literal :: (Functor m, InputParsing m, Applicative n, ParserInput m ~ s) => s -> Format m n s ()
byte    :: (InputParsing m, ParserInput m ~ ByteString) => Format m Identity ByteString Word8
cereal  :: (Serialize a, Monad m, InputParsing m, ParserInput m ~ ByteString) => Format m Identity ByteString a
matrix  :: (Applicative m, Monoid (n s)) => Word -> Word -> Format m n s a -> Format m n s [[a]]
record  :: (Rank2.Apply g, Rank2.Traversable g, Applicative m, Monoid (n s)) => g (Format m n s) -> Format m n s (g Identity)

literal s = Format{
   parse = void (string s),
   serialize = const (pure s)
   }

byte = Format{
   parse = ByteString.head <$> anyToken,
   serialize = Identity . ByteString.singleton}

cereal = Format p (Identity . runPut . put)
   where p = do i <- getInput
                case runGet ((,) <$> get <*> bytesRead) i
                   of Left err -> fail err
                      Right (a, len) -> count len anyToken Applicative.*> pure a

matrix width height item = Format{
   parse = count (fromIntegral height) (count (fromIntegral width) $ parse item),
   serialize = foldMap (foldMap $ serialize item)}

record formats = Format{
   parse = Rank2.traverse (fmap Identity . parse) formats,
   serialize = Rank2.foldMap Functor.getConst . Rank2.liftA2 serializeField formats
   }
   where serializeField format (Identity a) = Functor.Const (serialize format a)

f1 *> f2 = Format{
   parse = parse f1 Applicative.*> parse f2,
   serialize = \a-> serialize f1 () <> serialize f2 a}

f1 <* f2 = Format{
   parse = parse f1 Applicative.<* parse f2,
   serialize = serialize f1}

f1 <|> f2 = Format{
   parse = parse f1 Applicative.<|> parse f2,
   serialize = \a-> serialize f1 a Applicative.<|> serialize f2 a}

empty = Format{
   parse = Applicative.empty,
   serialize = const Applicative.empty}

mfix f = Format{
   parse = Monad.Fix.mfix (parse . f),
   serialize = \a-> serialize (f a) a}
