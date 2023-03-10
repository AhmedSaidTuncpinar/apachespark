#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Functions to install Spark in case the user directly downloads SparkR
# from CRAN.

#' Download and Install Apache Spark to a Local Directory
#'
#' \code{install.spark} downloads and installs Spark to a local directory if
#' it is not found. If SPARK_HOME is set in the environment, and that directory is found, that is
#' returned. The Spark version we use is the same as the SparkR version. Users can specify a desired
#' Hadoop version, the remote mirror site, and the directory where the package is installed locally.
#'
#' The full url of remote file is inferred from \code{mirrorUrl} and \code{hadoopVersion}.
#' \code{mirrorUrl} specifies the remote path to a Spark folder. It is followed by a subfolder
#' named after the Spark version (that corresponds to SparkR), and then the tar filename.
#' The filename is composed of four parts, i.e. [Spark version]-bin-[Hadoop version].tgz.
#' For example, the full path for a Spark 3.3.1 package from
#' \code{https://archive.apache.org} has path:
#' \code{http://archive.apache.org/dist/spark/spark-3.3.1/spark-3.3.1-bin-hadoop3.tgz}.
#' For \code{hadoopVersion = "without"}, [Hadoop version] in the filename is then
#' \code{without-hadoop}.
#'
#' @param hadoopVersion Version of Hadoop to install. Default is \code{"3"}.
#'                      If \code{hadoopVersion = "without"}, "Hadoop free" build is installed.
#'                      See
#'                      \href{https://spark.apache.org/docs/latest/hadoop-provided.html}{
#'                      "Hadoop Free" Build} for more information.
#'                      Other patched version names can also be used.
#' @param mirrorUrl base URL of the repositories to use. The directory layout should follow
#'                  \href{https://www.apache.org/dyn/closer.lua/spark/}{Apache mirrors}.
#' @param localDir a local directory where Spark is installed. The directory contains
#'                 version-specific folders of Spark packages. Default is path to
#'                 the cache directory:
#'                 \itemize{
#'                   \item Mac OS X: \file{~/Library/Caches/spark}
#'                   \item Unix: \env{$XDG_CACHE_HOME} if defined, otherwise \file{~/.cache/spark}
#'                   \item Windows: \file{\%LOCALAPPDATA\%\\Apache\\Spark\\Cache}.
#'                 }
#' @param overwrite If \code{TRUE}, download and overwrite the existing tar file in localDir
#'                  and force re-install Spark (in case the local directory or file is corrupted)
#' @return the (invisible) local directory where Spark is found or installed
#' @rdname install.spark
#' @name install.spark
#' @aliases install.spark
#' @examples
#'\dontrun{
#' install.spark()
#'}
#' @note install.spark since 2.1.0
#' @seealso See available Hadoop versions:
#'          \href{https://spark.apache.org/downloads.html}{Apache Spark}
install.spark <- function(hadoopVersion = "3", mirrorUrl = NULL,
                          localDir = NULL, overwrite = FALSE) {
  sparkHome <- Sys.getenv("SPARK_HOME")
  if (isSparkRShell()) {
    stopifnot(nchar(sparkHome) > 0)
    message("Spark is already running in sparkR shell.")
    return(invisible(sparkHome))
  } else if (!is.na(file.info(sparkHome)$isdir)) {
    message("Spark package found in SPARK_HOME: ", sparkHome)
    return(invisible(sparkHome))
  }

  version <- paste0("spark-", packageVersion("SparkR"))
  hadoopVersion <- tolower(hadoopVersion)
  hadoopVersionName <- hadoopVersionName(hadoopVersion)
  packageName <- paste(version, "bin", hadoopVersionName, sep = "-")
  localDir <- ifelse(is.null(localDir), sparkCachePath(),
                     normalizePath(localDir, mustWork = FALSE))

  if (is.na(file.info(localDir)$isdir)) {
    dir.create(localDir, recursive = TRUE)
  }

  if (overwrite) {
    message("Overwrite = TRUE: download and overwrite the tar file",
            "and Spark package directory if they exist.")
  }

  releaseUrl <- Sys.getenv("SPARKR_RELEASE_DOWNLOAD_URL")
  if (releaseUrl != "") {
    packageName <- basenameSansExtFromUrl(releaseUrl)
  }

  packageLocalDir <- file.path(localDir, packageName)

  # can use dir.exists(packageLocalDir) under R 3.2.0 or later
  if (!is.na(file.info(packageLocalDir)$isdir) && !overwrite) {
    if (releaseUrl != "") {
      message(packageName, " found, setting SPARK_HOME to ", packageLocalDir)
    } else {
      message(version, " for Hadoop ",
              if (hadoopVersion == "without") "Free build" else hadoopVersion,
              " found, setting SPARK_HOME to ", packageLocalDir)
    }
    Sys.setenv(SPARK_HOME = packageLocalDir)
    return(invisible(packageLocalDir))
  } else {
    message("Spark not found in the cache directory. Installation will start.")
  }

  packageLocalPath <- paste0(packageLocalDir, ".tgz")
  tarExists <- file.exists(packageLocalPath)

  if (tarExists && !overwrite) {
    message("tar file found.")
  } else {
    if (releaseUrl != "") {
      message("Downloading from alternate URL:\n- ", releaseUrl)
      success <- downloadUrl(releaseUrl, packageLocalPath)
      if (!success) {
        unlink(packageLocalPath)
        stop("Fetch failed from ", releaseUrl)
      }
    } else {
      robustDownloadTar(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath)
    }
  }

  message("Installing to ", localDir)
  # There are two ways untar can fail - untar could stop() on errors like incomplete block on file
  # or, tar command can return failure code
  success <- tryCatch(untar(tarfile = packageLocalPath, exdir = localDir) == 0,
                     error = function(e) {
                       message(e, "\n")
                       FALSE
                     },
                     warning = function(w) {
                       message(w, "\n")
                       FALSE
                     })
  if (!tarExists || overwrite || !success) {
    unlink(packageLocalPath)
    if (success) {
      # if tar file was not there before (or it was, but we are told to overwrite it),
      # and untar is successful - set a flag that we have downloaded (and untar) Spark package.
      assign(".sparkDownloaded", TRUE, envir = .sparkREnv)
    }
  }
  if (!success) stop("Extract archive failed.")
  message("DONE.")
  Sys.setenv(SPARK_HOME = packageLocalDir)
  message("SPARK_HOME set to ", packageLocalDir)
  invisible(packageLocalDir)
}

robustDownloadTar <- function(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath) {
  # step 1: use user-provided url
  if (!is.null(mirrorUrl)) {
    message("Use user-provided mirror site: ", mirrorUrl)
    success <- directDownloadTar(mirrorUrl, version, hadoopVersion,
                                   packageName, packageLocalPath)
    if (success) {
      return()
    } else {
      message("Unable to download from mirrorUrl: ", mirrorUrl)
    }
  } else {
    message("MirrorUrl not provided.")
  }

  # step 2: use url suggested from apache website
  message("Looking for preferred site from apache website...")
  mirrorUrl <- getPreferredMirror(version, packageName)
  if (!is.null(mirrorUrl)) {
    success <- directDownloadTar(mirrorUrl, version, hadoopVersion,
                                   packageName, packageLocalPath)
    if (success) return()
  } else {
    message("Unable to download from preferred mirror site: ", mirrorUrl)
  }

  # step 3: use backup option
  message("To use backup site...")
  mirrorUrl <- defaultMirrorUrl()
  success <- directDownloadTar(mirrorUrl, version, hadoopVersion,
                                 packageName, packageLocalPath)
  if (success) {
    return()
  } else {
    # remove any partially downloaded file
    unlink(packageLocalPath)
    message("Unable to download from default mirror site: ", mirrorUrl)
    stop("Unable to download Spark ", version,
         " for Hadoop ", if (hadoopVersion == "without") "Free build" else hadoopVersion,
         ". Please check network connection, Hadoop version, or provide other mirror sites.")
  }
}

getPreferredMirror <- function(version, packageName) {
  jsonUrl <- paste0("http://www.apache.org/dyn/closer.cgi?path=",
                        file.path("spark", version, packageName),
                        ".tgz&as_json=1")
  textLines <- readLines(jsonUrl, warn = FALSE)
  rowNum <- grep('"preferred"', textLines, fixed = TRUE)
  linePreferred <- textLines[rowNum]
  matchInfo <- regexpr('"[A-Za-z][A-Za-z0-9+-.]*://.+"', linePreferred)
  if (matchInfo != -1) {
    startPos <- matchInfo + 1
    endPos <- matchInfo + attr(matchInfo, "match.length") - 2
    mirrorPreferred <- base::substr(linePreferred, startPos, endPos)
    mirrorPreferred <- paste0(mirrorPreferred, "spark")
    message("Preferred mirror site found: ", mirrorPreferred)
  } else {
    mirrorPreferred <- NULL
  }
  mirrorPreferred
}

directDownloadTar <- function(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath) {
  packageRemotePath <- paste0(file.path(mirrorUrl, version, packageName), ".tgz")
  message("Downloading ", version, " for Hadoop ",
          if (hadoopVersion == "without") "Free build" else hadoopVersion,
          " from:\n- ", packageRemotePath)
  downloadUrl(packageRemotePath, packageLocalPath)
}

downloadUrl <- function(remotePath, localPath) {
  isFail <- tryCatch(download.file(remotePath, localPath),
                     error = function(e) {
                       message(e, "\n")
                       TRUE
                     },
                     warning = function(w) {
                       message(w, "\n")
                       TRUE
                     })
  !isFail
}

defaultMirrorUrl <- function() {
  "http://www-us.apache.org/dist/spark"
}

hadoopVersionName <- function(hadoopVersion) {
  if (hadoopVersion == "without") {
    "without-hadoop"
  } else if (grepl("^[0-9]+$", hadoopVersion, perl = TRUE)) {
    paste0("hadoop", hadoopVersion)
  } else {
    hadoopVersion
  }
}

# The implementation refers to appdirs package: https://pypi.python.org/pypi/appdirs and
# adapt to Spark context
# see also sparkCacheRelPathLength()
sparkCachePath <- function() {
  if (is_windows()) {
    winAppPath <- Sys.getenv("LOCALAPPDATA", unset = NA)
    if (is.na(winAppPath)) {
      message("%LOCALAPPDATA% not found. Falling back to %USERPROFILE%.")
      winAppPath <- Sys.getenv("USERPROFILE", unset = NA)
    }
    if (is.na(winAppPath)) {
      stop("%LOCALAPPDATA% and %USERPROFILE% not found. ",
           "Please define the environment variable ",
           "or restart and enter an installation path in localDir.")
    } else {
      path <- file.path(winAppPath, "Apache", "Spark", "Cache")
    }
  } else if (.Platform$OS.type == "unix") {
    if (Sys.info()["sysname"] == "Darwin") {
      path <- file.path(Sys.getenv("HOME"), "Library", "Caches", "spark")
    } else {
      path <- file.path(
        Sys.getenv("XDG_CACHE_HOME", file.path(Sys.getenv("HOME"), ".cache")), "spark")
    }
  } else {
    stop("Unknown OS: ", .Platform$OS.type)
  }
  normalizePath(path, mustWork = FALSE)
}

# Length of the Spark cache specific relative path segments for each platform
# e.g. "Apache\Spark\Cache" is 3 in Windows, or "spark" is 1 in unix
# Must match sparkCachePath() exactly.
sparkCacheRelPathLength <- function() {
  if (is_windows()) {
    3
  } else {
    1
  }
}

installInstruction <- function(mode) {
  if (mode == "remote") {
    paste0("Connecting to a remote Spark master. ",
           "Please make sure Spark package is also installed in this machine.\n",
           "- If there is one, set the path in sparkHome parameter or ",
           "environment variable SPARK_HOME.\n",
           "- If not, you may run install.spark function to do the job. ",
           "Please make sure the Spark and the Hadoop versions ",
           "match the versions on the cluster. ",
           "SparkR package is compatible with Spark ", packageVersion("SparkR"), ".",
           "If you need further help, ",
           "contact the administrators of the cluster.")
  } else {
    stop("No instruction found for mode ", mode)
  }
}

uninstallDownloadedSpark <- function() {
  # clean up if Spark was downloaded
  sparkDownloaded <- getOne(".sparkDownloaded",
                            envir = .sparkREnv,
                            inherits = TRUE,
                            ifnotfound = FALSE)
  sparkDownloadedDir <- Sys.getenv("SPARK_HOME")
  if (sparkDownloaded && nchar(sparkDownloadedDir) > 0) {
    unlink(sparkDownloadedDir, recursive = TRUE, force = TRUE)

    dirs <- traverseParentDirs(sparkCachePath(), sparkCacheRelPathLength())
    lapply(dirs, function(d) {
      if (length(list.files(d, all.files = TRUE, include.dirs = TRUE, no.. = TRUE)) == 0) {
        unlink(d, recursive = TRUE, force = TRUE)
      }
    })
  }
}
