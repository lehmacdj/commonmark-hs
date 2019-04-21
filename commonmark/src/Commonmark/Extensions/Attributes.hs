{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE OverloadedStrings #-}
module Commonmark.Extensions.Attributes
  ( Attributes(..)
  , HasAttributes(..)
  , headerAttributesSpec
  )
where
import Commonmark.Types
import Commonmark.Tokens
import Commonmark.Syntax
import Commonmark.Inlines
import Commonmark.SourceMap
import Commonmark.Util
import Commonmark.Blocks
import Commonmark.Html (escapeHtml, addAttribute, HtmlAttribute)
import Data.Dynamic
import qualified Data.Text as T
import Data.Tree
import Control.Monad (mzero)
import Text.Parsec
import Data.Text (Text)
import Data.Semigroup (Semigroup(..))

headerAttributesSpec
             :: (Monad m, IsBlock il bl, IsInline il, HasAttributes bl)
             => SyntaxSpec m il bl
headerAttributesSpec = SyntaxSpec
  { syntaxBlockSpecs = [atxHeaderWithAttributesSpec]
  , syntaxBracketedSpecs = []
  , syntaxFormattingSpecs = []
  , syntaxInlineParsers = []
  , syntaxFinalParsers = []
  }

class HasAttributes a where
  addAttributes :: Attributes -> a -> a

instance HasAttributes (Html a) where
  addAttributes attrs x = foldr addAttribute x attrs

instance HasAttributes (WithSourceMap a) where
  addAttributes _attrs x = x

type Attributes = [HtmlAttribute]

atxHeaderWithAttributesSpec
    :: (Monad m, IsBlock il bl, IsInline il, HasAttributes bl)
    => BlockSpec m il bl
atxHeaderWithAttributesSpec = atxHeaderSpec
  { blockType = "ATXHeaderWithAttributes"
  , blockStart = do
       res <- blockStart atxHeaderSpec
       nodestack <- nodeStack <$> getState
       case nodestack of
         [] -> mzero
         (Node nd cs:ns) -> updateState $ \st -> st{
              nodeStack = Node nd{ blockSpec = atxHeaderWithAttributesSpec
                                 } cs : ns }
       return res
  , blockConstructor    = \node -> do
       let level = fromDyn (blockData (rootLabel node)) 1
       let toks = getBlockText removeIndent node
       let (content, attr) = parseAttributes toks
       ils <- runInlineParser content
       return $ (addRange node . addAttributes attr . header level) ils
  }

parseAttributes :: [Tok] -> ([Tok], Attributes)
parseAttributes ts =
  case parse
       ((,) <$> many (notFollowedBy pAttributes >> anyTok)
            <*> option [] pAttributes) "heading contents" ts of
    Left _        -> (ts, [])
    Right (xs,ys) -> (xs, collapseAttrs ys)
  where
    collapseAttrs xs =
      let classes = [y | ("class", y) <- xs] in
     (case lookup "id" xs of
         Just id' -> (("id",id'):)
         Nothing  -> id) .
      (if null classes
          then id
          else (("class", T.unwords classes):)) $
      [(k,v) | (k,v) <- xs, k /= "id" && k /= "class"]

pAttributes :: Monad m => ParsecT [Tok] u m Attributes
pAttributes = try $ do
  symbol '{'
  optional whitespace
  let pAttribute = pIdentifier <|> pClass <|> pKeyValue
  a <- pAttribute
  as <- many $ try (whitespace *> (pIdentifier <|> pClass <|> pKeyValue))
  optional whitespace
  symbol '}'
  return (a:as)

pIdentifier :: Monad m => ParsecT [Tok] u m HtmlAttribute
pIdentifier = try $ do
  symbol '#'
  xs <- many1 $
        satisfyWord (const True)
    <|> satisfyTok (\c -> hasType (Symbol '-') c || hasType (Symbol '_') c
                        || hasType (Symbol ':') c || hasType (Symbol '.') c)
  return ("id", untokenize xs)

pClass :: Monad m => ParsecT [Tok] u m HtmlAttribute
pClass = do
  symbol '.'
  xs <- many1 $
        satisfyWord (const True)
    <|> satisfyTok (\c -> hasType (Symbol '-') c || hasType (Symbol '_') c)
  return ("class", untokenize xs)

pKeyValue :: Monad m => ParsecT [Tok] u m HtmlAttribute
pKeyValue = mzero

