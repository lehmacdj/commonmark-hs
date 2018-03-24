{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE OverloadedStrings #-}
module Commonmark.Extensions.Autolink
  ( autolinkSpec )
where
import Commonmark.Types
import Commonmark.Tokens
import Commonmark.Syntax
import Commonmark.Inlines
import Commonmark.Util
import Data.List (dropWhileEnd)
import Text.Parsec
import Data.Text (Text)
#if !MIN_VERSION_base(4,11,0)
import Data.Monoid
#endif

autolinkSpec :: (Monad m, IsBlock il bl, IsInline il)
             => SyntaxSpec m il bl
autolinkSpec = SyntaxSpec
  { syntaxBlockSpecs = []
  , syntaxBracketedSpecs = []
  , syntaxFormattingSpecs = []
  , syntaxInlineParsers = [parseAutolink]
  }

parseAutolink :: (Monad m, IsInline a) => InlineParser m a
parseAutolink = do
  (prefix, linktext) <- withRaw $ wwwAutolink <|> urlAutolink <|> emailAutolink
  return $ link (prefix <> untokenize linktext) "" (str . untokenize $ linktext)

wwwAutolink :: Monad m => InlineParser m Text
wwwAutolink = try $ do
  lookAhead $ satisfyWord (== "www")
  validDomain
  linkSuffix
  return "http://"

validDomain :: Monad m => InlineParser m ()
validDomain = do
  let domainPart = many1 $ satisfyTok (hasType WordChars)
                           <|> symbol '-'
                           <|> symbol '_'
  domainPart
  skipMany1 $ try (symbol '.' >> domainPart)

linkSuffix :: Monad m => InlineParser m ()
linkSuffix = try $ do
  toks <- getInput
  let possibleSuffixTok (Tok (Symbol c) _ _) = c /= '<'
      possibleSuffixTok (Tok WordChars _ _) = True
      possibleSuffixTok _ = False
  let isDroppable (Tok (Symbol c) _ _) =
         c `elem` ['?','!','.',',',':','*','_','~']
      isDroppable _ = False
  let chunk' = dropWhileEnd isDroppable $ takeWhile possibleSuffixTok toks
  let numToks = length chunk'
  count numToks anyTok
  return ()

urlAutolink :: Monad m => InlineParser m Text
urlAutolink = try $ do
  satisfyWord (`elem` ["http", "https", "ftp"])
  symbol ':'
  symbol '/'
  symbol '/'
  validDomain
  linkSuffix
  return ""

emailAutolink :: Monad m => InlineParser m Text
emailAutolink = try $ do
  let emailNameTok (Tok WordChars _ _) = True
      emailNameTok (Tok (Symbol c) _ _) =
         c == '.' || c == '-' || c == '_' || c == '+'
      emailNameTok _ = False
  skipMany1 $ satisfyTok emailNameTok
  symbol '@'
  validDomain
  return "mailto:"
