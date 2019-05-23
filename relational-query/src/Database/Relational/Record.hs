{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- |
-- Module      : Database.Relational.Record
-- Copyright   : 2013-2017 Kei Hibino
-- License     : BSD3
--
-- Maintainer  : ex8k.hibino@gmail.com
-- Stability   : experimental
-- Portability : unknown
--
-- This module defines interfaces of projected record type.
module Database.Relational.Record (
  -- * Record types
  Record, Predicate, PI,

  -- * Record and Table
  unsafeFromTable,

  -- * Projections
  pi, piMaybe, piMaybe',
  wpi,

  flattenMaybe, just,

  unsafeToAggregated, unsafeToFlat, unsafeChangeContext,
  unsafeStringSqlNotNullMaybe,

  -- * List of Record
  RecordList, list, unsafeListFromSubQuery,
  unsafeStringSqlList
  ) where

import Prelude hiding (pi)
import Data.Functor.ProductIsomorphic
  (ProductIsoFunctor, (|$|), ProductIsoApplicative, pureP, (|*|),
   ProductIsoEmpty, pureE, peRight, peLeft, )

import qualified Language.SQL.Keyword as SQL

import Database.Record (HasColumnConstraint, NotNull, NotNullColumnConstraint, PersistableWidth, persistableWidth)
import Database.Record.Persistable (PersistableRecordWidth)
import qualified Database.Record.KeyConstraint as KeyConstraint

import Database.Relational.Internal.ContextType (Aggregated, Flat)
import Database.Relational.Internal.String (StringSQL, listStringSQL)
import Database.Relational.SqlSyntax (SubQuery, showSQL)
import Database.Relational.Typed.Record
  (Record, record, untypeRecord, recordColumns, unsafeRecordFromColumns,
   Predicate, PI)

import Database.Relational.Table (Table)
import qualified Database.Relational.Table as Table
import Database.Relational.Pi (Pi)
import qualified Database.Relational.Pi.Unsafe as UnsafePi


-- | Unsafely generate unqualified 'Record' from 'Table'.
unsafeFromTable :: Table r
                -> Record c r
unsafeFromTable = unsafeRecordFromColumns . Table.columns

-- | Unsafely trace projection path.
unsafeProject :: PersistableRecordWidth a -> Record c a' -> Pi a b -> Record c b'
unsafeProject w p pi' =
  unsafeRecordFromColumns
  . (UnsafePi.pi w pi')
  . recordColumns $ p

-- | Trace projection path to get narrower 'Record'.
wpi :: PersistableRecordWidth a
    -> Record c a -- ^ Source 'Record'
    -> Pi a b     -- ^ Projection path
    -> Record c b -- ^ Narrower 'Record'
wpi =  unsafeProject

-- | Trace projection path to get narrower 'Record'.
pi :: PersistableWidth a
   => Record c a -- ^ Source 'Record'
   -> Pi a b     -- ^ Record path
   -> Record c b -- ^ Narrower 'Record'
pi =  unsafeProject persistableWidth

-- | Trace projection path to get narrower 'Record'. From 'Maybe' type to 'Maybe' type.
piMaybe :: PersistableWidth a
        => Record c (Maybe a) -- ^ Source 'Record'. 'Maybe' type
        -> Pi a b             -- ^ Projection path
        -> Record c (Maybe b) -- ^ Narrower 'Record'. 'Maybe' type result
piMaybe = unsafeProject persistableWidth

-- | Trace projection path to get narrower 'Record'. From 'Maybe' type to 'Maybe' type.
--   Leaf type of projection path is 'Maybe'.
piMaybe' :: PersistableWidth a
         => Record c (Maybe a) -- ^ Source 'Record'. 'Maybe' type
         -> Pi a (Maybe b)     -- ^ Projection path. 'Maybe' type leaf
         -> Record c (Maybe b) -- ^ Narrower 'Record'. 'Maybe' type result
piMaybe' = unsafeProject persistableWidth

unsafeCast :: Record c r -> Record c r'
unsafeCast = record . untypeRecord

-- | Composite nested 'Maybe' on record phantom type.
flattenMaybe :: Record c (Maybe (Maybe a)) -> Record c (Maybe a)
flattenMaybe =  unsafeCast

-- | Cast into 'Maybe' on record phantom type.
just :: Record c r -> Record c (Maybe r)
just =  unsafeCast

-- | Unsafely cast context type tag.
unsafeChangeContext :: Record c r -> Record c' r
unsafeChangeContext = record . untypeRecord

-- | Unsafely lift to aggregated context.
unsafeToAggregated :: Record Flat r -> Record Aggregated r
unsafeToAggregated =  unsafeChangeContext

-- | Unsafely down to flat context.
unsafeToFlat :: Record Aggregated r -> Record Flat r
unsafeToFlat =  unsafeChangeContext

notNullMaybeConstraint :: HasColumnConstraint NotNull r => Record c (Maybe r) -> NotNullColumnConstraint r
notNullMaybeConstraint =  const KeyConstraint.columnConstraint

-- | Unsafely get SQL string expression of not null key record.
unsafeStringSqlNotNullMaybe :: HasColumnConstraint NotNull r => Record c (Maybe r) -> StringSQL
unsafeStringSqlNotNullMaybe p = (!!  KeyConstraint.index (notNullMaybeConstraint p)) . recordColumns $ p

pempty :: Record c ()
pempty = record []

-- | Map 'Record' which result type is record.
instance ProductIsoFunctor (Record c) where
  _ |$| p = unsafeCast p

-- | Compose 'Record' using applicative style.
instance ProductIsoApplicative (Record c) where
  pureP _ = unsafeCast pempty
  pf |*| pa = record $ untypeRecord pf ++ untypeRecord pa

instance ProductIsoEmpty (Record c) () where
  pureE   = pureP ()
  peRight = unsafeCast
  peLeft  = unsafeCast

-- | Projected record list type for row list.
data RecordList p t = List [p t]
                    | Sub SubQuery

-- | Make projected record list from 'Record' list.
list :: [p t] -> RecordList p t
list =  List

-- | Make projected record list from 'SubQuery'.
unsafeListFromSubQuery :: SubQuery -> RecordList p t
unsafeListFromSubQuery =  Sub

-- | Map record show operatoions and concatinate to single SQL expression.
unsafeStringSqlList :: (p t -> StringSQL) -> RecordList p t -> StringSQL
unsafeStringSqlList sf = d  where
  d (List ps) = listStringSQL $ map sf ps
  d (Sub sub) = SQL.paren $ showSQL sub
