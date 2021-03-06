-- csv-to-fasta
-- By Gregory W. Schwartz

-- Takes a csv file and return a fasta file where each sequence was from
-- a column in the csv file

-- Cabal
import Options.Applicative
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.IO as TIO

-- Local
import Types
import Parse
import Print

-- Command line arguments
data Options = Options { inputHeaders    :: String
                       , inputHeaderCols :: String
                       , inputSeqs       :: String
                       , inputSeqsCol    :: Int
                       , inputGerm       :: String
                       , inputGermCol    :: Int
                       , inputClone      :: String
                       , inputCloneCol   :: Int
                       , inputLabel      :: String
                       , inputSep        :: String
                       , noHeader        :: Bool
                       , includeGermline :: Bool
                       , includeClone    :: Bool
                       , sortCloneFlag   :: Bool
                       , input           :: String
                       , output          :: String
                       }

-- Command line options
options :: Parser Options
options = Options
      <$> strOption
          ( long "headers"
         <> short 'n'
         <> metavar "STRING"
         <> value ""
         <> help "The column names headers separated by a space.\
                 \ Appears in the header in the order given. Has preference\
                 \ over header-cols" )
      <*> strOption
          ( long "header-cols"
         <> short 'N'
         <> metavar "INT"
         <> value "-1"
         <> help "The column numbers for the header separated by a space.\
                 \ Appears in the header in the order given" )
      <*> strOption
          ( long "seqs"
         <> short 's'
         <> metavar "STRING"
         <> value ""
         <> help "The column name for the sequences. Has preference over\
                 \ seqs-col" )
      <*> option auto
          ( long "seqs-col"
         <> short 'S'
         <> metavar "INT"
         <> value 1
         <> help "The column number for the sequences" )
      <*> strOption
          ( long "germline"
         <> short 'g'
         <> metavar "STRING"
         <> value ""
         <> help "The column name for the germline sequences. \
                 \ Has preference over germline-col" )
      <*> option auto
          ( long "germline-col"
         <> short 'G'
         <> metavar "INT"
         <> value 1
         <> help "The column number for the germline sequences" )
      <*> strOption
          ( long "clone"
         <> short 'c'
         <> metavar "STRING"
         <> value ""
         <> help "The column name for the clone ID. Requires germline column.\
                 \ Has preference over clone-col" )
      <*> option auto
          ( long "clone-col"
         <> short 'C'
         <> metavar "INT"
         <> value 1
         <> help "The column number for the clone ID.\
                 \ Requires germline column" )
      <*> strOption
          ( long "label"
         <> short 'l'
         <> metavar "STRING"
         <> value ""
         <> help "An optional label to be added at the end of the header" )
      <*> strOption
          ( long "sep"
         <> short 'e'
         <> metavar "STRING"
         <> value ","
         <> help "The csv delimiter" )
      <*> switch
          ( long "no-header"
         <> short 'h'
         <> help "Whether the csv contains a header" )
      <*> switch
          ( long "include-germline"
         <> short 'p'
         <> help "Whether to include the germline in CLIP fasta style\
                 \ formatting" )
      <*> switch
          ( long "include-clone"
         <> short 'P'
         <> help "Whether to include the clones in CLIP fasta style\
                 \ formatting (needs include-germline)" )
      <*> switch
          ( long "clone-no-sort"
         <> short 'P'
         <> help "Whether to bypass sorting fasta sequences by clone before\
                 \categorizing clones for the CLIP fasta. If true, the\
                 \ list will not be sorted and only sequential sequences in\
                 \ the file will be checked and joined for the same clone" )
      <*> strOption
          ( long "input"
         <> short 'i'
         <> metavar "FILE"
         <> value ""
         <> help "The input csv file" )
      <*> strOption
          ( long "output"
         <> short 'o'
         <> metavar "FILE"
         <> value ""
         <> help "The output fasta file" )

-- | Removes empty lines
lineCompress :: String -> String
lineCompress []        = []
lineCompress ('\n':xs) = '\n' : (lineCompress $ dropWhile (== '\n') xs)
lineCompress (x:xs)    = x : (lineCompress xs)

-- | Removes empty lines text version
lineCompressText :: T.Text -> T.Text
lineCompressText = T.unlines . filter (not . T.null) . T.lines

csvToFasta :: Options -> IO ()
csvToFasta opts = do
    contentsCarriages <- if null . input $ opts
                            then TIO.getContents
                            else TIO.readFile . input $ opts
    -- Get rid of carriages
    let headers             = T.words . T.pack . inputHeaders $ opts
        headerCols          = map (\x -> read x :: Int)
                            . words
                            . inputHeaderCols
                            $ opts
        seqs                = T.pack . inputSeqs $ opts
        seqCol              = inputSeqsCol opts
        germ                = T.pack . inputGerm $ opts
        germCol             = inputGermCol opts
        clone               = T.pack . inputClone $ opts
        cloneCol            = inputCloneCol opts
        label               = T.pack . inputLabel $ opts
        sep                 = if inputSep opts == "\\t"
                                  then T.pack "\t"
                                  else T.pack . inputSep $ opts
        contents            = lineCompressText
                            . T.map (\x -> if x == '\r' then '\n' else x)
                            $ contentsCarriages
        unfilteredFastaList = parseCSV
                              (noHeader opts)
                              (includeGermline opts)
                              (includeClone opts)
                              headers
                              headerCols
                              seqs
                              seqCol
                              germ
                              germCol
                              clone
                              cloneCol
                              sep
                              contents
        unlabeledFastaList  = filter (not . T.null . fastaSeq)
                              unfilteredFastaList
        fastaList           = if T.null label
                                  then unlabeledFastaList
                                  else map
                                       (\x
                                      -> x { fastaInfo = label
                                              `T.append` (T.pack "|")
                                              `T.append` fastaInfo x } )
                                         unlabeledFastaList


    -- Save results
    if null . output $ opts
        then TIO.putStrLn
           . printFasta (includeClone opts) (sortCloneFlag opts)
           $ fastaList
        else TIO.writeFile (output opts)
           . printFasta (includeClone opts) (sortCloneFlag opts)
           $ fastaList

main :: IO ()
main = execParser opts >>= csvToFasta
  where
    opts = info (helper <*> options)
      ( fullDesc
     <> progDesc "Convert a csv file to a fasta file"
     <> header "csv-to-fasta, Gregory W. Schwartz" )
