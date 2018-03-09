filterIso <- function(isodf, network) {
    # Function to filter isotopes data.frame,
    # and to create a network of isotopes
    isodfSorted <- isodf[,c("pfeature", "ifeature")]
    isodfSorted <- (apply(isodfSorted, 1 , sort, decreasing = F))
    isodf$weight <- igraph::E(network,
                              P = as.numeric(isodfSorted))$weight
    #as.numeric is important to acces correct weight values
    #First filter isotopes pointing to two different parents
    inlinks <- as.numeric(names(
        which(table(isodf[,"ifeature"]) > 1)))
    badpfeatures <- unlist(lapply(inlinks, function(x) {
        rowpfeatures <- which(isodf$ifeature == x)
        #drop the parental feature with less weight
        dropRows <- rowpfeatures[-1*which.max(
            isodf[rowpfeatures,"weight"])]
    }))
    if( length(badpfeatures) > 0 ) {
        isodf <- isodf[-1*badpfeatures,]
    }
    #Second filter parents pointed by two diferent isotopes
    outlinks <- as.numeric(names(
        which(table(isodf[,"pfeature"]) > 1)))
    badifeatures <- unlist(lapply(outlinks, function(x) {
        rowifeatures <- which(isodf$pfeature == x)
        #drop the parental feature with less weight
        dropRows <- rowifeatures[-1*which.max(
        isodf[rowifeatures,"weight"])]
    }))
    if( length(badifeatures) > 0 ) {
        isodf <- isodf[-1*badifeatures,]
    }
    #Third filter inconsistency in charge
    allnodes <- unique(c(isodf[,"pfeature",],isodf[,"ifeature"]))
    badisoCharge <- unlist(lapply(allnodes, function(x) {
        res <- integer()
        posp <- which(isodf$pfeature == x)
        if( length(posp) > 0 ) {
            posi <- which(isodf$ifeature == x)
            if( length(posi) > 0 ) {
                if(isodf[posp,"pcharge"] != isodf[posi,"icharge"]) {
                    res <- c(posp, posi)
                }
            }
        }
        res
    }))
    if( length(badisoCharge) > 0 ) {
        isodf <- isodf[-1*badisoCharge,]
    }
    # Finally create the filtered isotope network
    isonet <- igraph::graph.data.frame(isodf[,c("ifeature","pfeature")])
    return(list(network = isonet, isodf = isodf))
}

isoGrade <- function(isonet) {
    # Function to grade and isotope, starting from 0 to the parental isotpe, 1 the first isotope and further
    grades <- sapply(igraph::V(isonet), function(x) {
        res <- 0
        nei <- igraph::neighbors(isonet, v = x, mode = "out")
        while(length(nei) > 0) {
            res <- res + 1
            nei <- igraph::neighbors(isonet, v = nei, mode = "out")
        }
        res
    })
    return(grades)
}

isonetAttributes <- function(isolist) {
    # Function to set the node attributes for each isotope:
    # grade, charge, and community
    # First assign grade (for info look isoGrade function)
    igraph::V(isolist$network)$grade <- isoGrade(isolist$network)
    charge <- sapply(
        as.numeric(igraph::V(isolist$network)$name), function(x) {
            posp <- which(isolist$isodf[,"pfeature"] == x)
            if( length(posp) > 0 ) {
                res <- isolist$isodf[posp,"pcharge"]
            } else {
                posi <- which(isolist$isodf[,"ifeature"] == x)
                res <- isolist$isodf[posi,"icharge"]
            }
            res
        })
    # Second assign charge of each feature as isotope
    igraph::V(isolist$network)$charge <- charge
    # Third label features that belong to the same isotope cluster
    igraph::V(isolist$network)$cluster <- 
                                 igraph::clusters(isolist$network,
                                                  "weak")$membership
    # Final step write a table with all the isotope data
    isoTable <- data.frame(
        feature = as.numeric(igraph::V(isolist$network)$name),
        charge = igraph::V(isolist$network)$charge,
        grade = igraph::V(isolist$network)$grade,
        cluster = igraph::V(isolist$network)$cluster
    )
    return(isoTable)
}

addIso2peaklist <- function(isoTable, peaklist) {
    peaklist$isotope <- rep("M0", nrow(peaklist))
    peaklist$isotope[isoTable[,"feature"]] <- 
        paste(paste("M",isoTable$grade, sep = ""),
              paste("[",isoTable$cluster, "]",sep = ""),
              sep = " ")
    return(peaklist)
}
 

getIsotopes.anClique <- function(anclique, maxCharge = 3,
                                 maxGrade = 2, ppm = 10,
                                 isom = 1.003355) {
    # Function to get all the isotopes from the m/z data
    # after splitting it into clique groups
    if(anclique$isoFound == TRUE) {
        warning("Isotopes have been already computed for this object")
    }
    cat("Computing isotopes\n")
    listofisoTable <- lapply(anclique$cliques, function(x) {
        df.clique <- as.data.frame(
            cbind(anclique$peaklist[x, c("mz","maxo")],x)
        )
        colnames(df.clique) <- c("mz","maxo","feature")
        # Sort df.clique by intensity because isotopes are less
        # intense than their parental features
        df.clique <- df.clique[order(df.clique$maxo, decreasing = T),]
        # compute isotopes from clique
        isodf <- returnIsotopes(df.clique, maxCharge = maxCharge,
                               ppm = ppm,
                               isom = isom)
        if( nrow(isodf) > 0 ) {
            # filter the isotope list by charge
            # and other inconsistencies
            isolist <- filterIso(isodf, anclique$network)
            if( nrow(isolist$isodf) > 0 ) {
            # write a table with feature, charge, grade and cluster 
                iTable <- isonetAttributes(isolist)
            }
        } else {
            iTable = NULL
        }
        iTable
    })
    # The cluster label is inconsistent between all isotopes found
    # let's correct for avoiding confusions
    posMax <- 1
    while(is.null(listofisoTable[[posMax]])) {
        posMax = posMax + 1
    }
    maxVal <- max(listofisoTable[[posMax]]$cluster)
    for( i in 2:length(listofisoTable) ) {
        if( !is.null(listofisoTable[[i]]) ) {
            listofisoTable[[i]]$cluster =
                listofisoTable[[i]]$cluster + maxVal
            maxVal = max(listofisoTable[[i]]$cluster)
        }
    }
    cat("Updating anClique object\n")
    isoTable <- do.call(rbind, listofisoTable)
    rownames(isoTable) <- 1:nrow(isoTable)
    # Now change status of isotopes at anclique object
    anclique$isoFound <- TRUE
    # Put new isotopes table
    anclique$isotopes <- isoTable
    # And change the peaklist adding isotope column
    anclique$peaklist <- addIso2peaklist(isoTable,
                                        anclique$ peaklist)
    return(anclique)
}