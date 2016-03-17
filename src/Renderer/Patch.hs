patch diff sources = case getLast $ foldMap (Last . Just) string of
  Just c | c /= '\n' -> string ++ "\n\\ No newline at end of file\n"
  _ -> string
  where string = mconcat $ showHunk sources <$> hunks diff sources
showHunk blobs hunk = header blobs hunk ++
  concat (showChange sources <$> changes hunk) ++
  showLines (snd sources) ' ' (snd <$> trailingContext hunk)
          (Just mode, Nothing) -> intercalate "\n" [ "deleted file mode " ++ modeToDigits mode, blobOidHeader ]
            "old mode " ++ modeToDigits mode1,
            "new mode " ++ modeToDigits mode2,
            blobOidHeader
hunks _ blobs | sources <- source <$> blobs
              , sourcesEqual <- runBothWith (==) sources
              , sourcesNull <- runBothWith (&&) (null <$> sources)
              , sourcesEqual || sourcesNull
  = [Hunk { offset = mempty, changes = [], trailingContext = [] }]