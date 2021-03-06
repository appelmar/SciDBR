#' Update available AFL operators
#'
#' @param db an \code{afl} object (a SciDB database connection returned from \code{\link{scidbconnect}})
#' @param new a character vector of operator names
#' @param ops an optional three-variable data frame with variables name, signature, help, corresponding
#' to the operator names, signatures, and help files (from SciDB Doxygen documentation)
#' @return the updated database object
#' @keywords internal
#' @importFrom utils head
update.afl = function(db, new, ops)
{
  if (missing(ops))
  {
    e = new.env()
    data("operators", package="scidb", envir=e)
    ops = e$operators
  }
  conn = db  # need a reference to the scidb connection in the afl function below
  for (x in new)
  {
    db[[x]] = afl
    i = ops[, 1] == x
    # update formal function arguments for nice tab completion help
    if (any(i))
    {
      def = head(ops[i, ], 1)
      # XXX very ugly...
      fml = strsplit(gsub("[=:].*", "", gsub("\\|.*", "", gsub(" *", "", gsub("\\]", "", gsub("\\[", "", gsub("\\[.*\\|.*\\]", "", gsub("[+*{})]", "", gsub(".*\\(", "", def[2])))))))), ",")[[1]]
      formals(db[[x]]) = eval(parse(text=sprintf("alist(%s, ...=)", paste(paste(fml, "="), collapse=", "))))
      attr(db[[x]], "help") = def[3]
      attr(db[[x]], "signature") = def[2]
    }
    class(db[[x]]) = "operator"
    attr(db[[x]], "name") = x
    attr(db[[x]], "conn") = conn
  }
  db
}

#' Substitute scalar-valued R expressions into an AFL expression
#' R expressions are marked with R(expression)
#' @param x character valued AFL expression
#' @param env environment in which to evaluate R expressions
#' @return character valued AFL expression
#' @keywords internal function
rsub = function(x, env)
{
  if (! grepl("[^[:alnum:]_]R\\(", x)) return(x)
  imbalance_paren = function(x) # efficiently find the first imbalanced ")" character position
  {
    which (cumsum( (as.numeric(charToRaw(x) == charToRaw("("))) - (as.numeric(charToRaw(x) == charToRaw(")"))) ) < 0)[1]
  }
  y = gsub("([^[:alnum:]_])R\\(", "\\1@R(", x)
  y = strsplit(y, "@R\\(")[[1]]
  expr = Map(function(x)
  {
    i = imbalance_paren(x)
    rexp = eval(parse(text=substring(x, 1, i - 1)), envir=env)
    rmdr = substring(x, i + 1)
    paste(rexp, rmdr, sep="")
  }, y[-1])
  sprintf("%s%s", y[1], paste(expr, collapse=""))
}

#' Create an AFL expression
#' @param ... AFL expression argument list dynamically generated by \code{update.afl}, but see the note below
#' @note The call list expected to look like: \code{(afl arguments, ...)}
#' @return a \code{\link{scidb}} object
#' @keywords internal function
#' @importFrom utils capture.output
afl = function(...)
{
  call = eval(as.list(match.call())[[1]])
  .env = new.env()
  pf = parent.frame()
  .args = paste(
             lapply(as.list(match.call())[-1],
               function(.x) tryCatch({
                   if (class(eval(.x, envir=pf))[1] %in% "scidb") eval(.x, envir=pf)@name
                   else .x
               }, error=function(e) .x)),
         collapse=",")
  expr = sprintf("%s(%s)", attributes(call)$name, .args)
# handle aliasing
  expr = gsub("%as%", " as ", expr)
# handle R scalar variable substitutions
  expr = rsub(expr, pf)
# Some special AFL non-operator expressions don't return arrays
  if (any(grepl(attributes(call)$name, getOption("scidb.ddl"), ignore.case=TRUE)))
  {
    return(iquery(attributes(call)$conn, expr))
  }
  if (getOption("scidb.debug", FALSE)) message("AFL EXPRESSION: ", expr)
  ans = scidb(attributes(call)$conn, expr)
  ans@meta$depend = as.list(.env)
  ans
}

#' Display SciDB AFL operator documentation
#' @param topic an \code{\link{afl}} object from a SciDB database connection, or optionally a character string name
#' @param db optional database connection from \code{\link{scidbconnect}} (only needed when \code{topic} is a character string)
#' @return displays help
#' @examples
#' \dontrun{
#' d <- scidbconnect()
#' aflhelp("list", d)     # explicitly look up a character string
#' help(d$list)        # same thing via R's \code{help} function
#' }
#' @importFrom  utils data
#' @export
aflhelp = function(topic, db)
{
  if (is.character(topic))
  {
    if (missing(db)) stop("character topics require a database connection argument")
    topic = db[[topic]]
  }
  h = sprintf("%s\n\n%s", attr(topic, "signature"), gsub("\\n{2,}", "\n", attr(topic, "help")))
  message(h)
}
