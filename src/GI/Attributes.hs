module GI.Attributes
    ( genAttributes
    , genAllAttributes
    ) where

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative ((<$>))
#endif
import Control.Monad (forM_, when)
import qualified Data.Set as S
import qualified Data.Text as T
import Data.Text (Text)

import GI.API
import GI.Code
import GI.SymbolNaming
import GI.Properties

-- A list of distinct property names for all GObjects appearing in the
-- given list of APIs.
findObjectPropNames :: [(Name, API)] -> CodeGen [Text]
findObjectPropNames apis = S.toList <$> go apis S.empty
    where
      go :: [(Name, API)] -> S.Set Text -> CodeGen (S.Set Text)
      go [] set = return set
      go ((_, api):apis) set =
        case api of
          APIInterface iface ->
              go apis $ insertProps (ifProperties iface) set
          APIObject object ->
              go apis $ insertProps (objProperties object) set
          _ -> go apis set

      insertProps :: [Property] -> S.Set Text -> S.Set Text
      insertProps props set = S.union set ((S.fromList . map propName) props)

genPropertyAttr :: Text -> CodeGen ()
genPropertyAttr pName = group $ do
  line $ "-- Property \"" ++ T.unpack pName ++ "\""
  let name = (hyphensToCamelCase  . T.unpack) pName
  line $ "_" ++ lcFirst name ++ " :: Proxy \"" ++ T.unpack pName ++ "\""
  line $ "_" ++ lcFirst name ++ " = Proxy"

genAllAttributes :: [(Name, API)] -> CodeGen ()
genAllAttributes allAPIs = do
  line "-- Generated code."
  blank
  line "{-# LANGUAGE DataKinds #-}"
  blank

  moduleName <- currentModule
  line $ "module " ++ T.unpack moduleName ++ " where"
  blank
  line $ "import Data.Proxy (Proxy(..))"
  blank

  propNames <- findObjectPropNames allAPIs
  forM_ propNames $ \name -> do
      genPropertyAttr name
      blank

genProps :: (Name, API) -> CodeGen ()
genProps (n, APIObject o) = genObjectProperties n o
genProps (n, APIInterface i) = genInterfaceProperties n i
genProps _ = return ()

genAttributes :: String -> [(Name, API)] -> CodeGen ()
genAttributes name apis = do
  let mp = ("GI." ++)
      nm = ucFirst name

  code <- recurse $ forM_ apis genProps

  -- Providing orphan instances is the whole point of these modules,
  -- tell GHC that this is fine.
  line "{-# OPTIONS_GHC -fno-warn-orphans -fno-warn-unused-imports #-}"
  blank

  deps <- map T.unpack <$> S.toList <$> getDeps
  forM_ deps $ \i -> when (i /= name) $ do
    line $ "import qualified " ++ mp (ucFirst i) ++ " as " ++ ucFirst i
    line $ "import qualified " ++ mp (ucFirst i) ++ ".Attributes as "
             ++ ucFirst i ++ "A"

  line $ "import " ++ mp nm
  blank

  tellCode code
