# Author:  <wblake@3C5XT34>
# Created: Feb 02, 2026
# Version: 0.01
#
# Usage: perl [-d] isbn2bid.pl [-r ] [-x] [-g] filename.csv
# -d Debug/verbose captured by perl exe, remaining options left for this script
# -g Logging
# checked but not used: -r, -x
# filename.csv is a file ISBN numbers
# Warning.
# Input file filename.csv should only have ISBN values that exist in the CarlX catlog
# isbn2bid will report the bid and other CarlX Catalog fields to every account listed.
# Only the isbn column really matters but the Input CSV file column order goes:
# $isbn,$title, $author, $callnuber
#
#Debug mode- a lot more SOAP messages.=
#
# Assumes first line of in file has column label headings
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for interface to PatronAPI requests AddPatronNote
#
# A tool like SOAPUI can provide a sandbox for the WSDL file and PatronAPI requests.
#
# Note that API call and response return appear to take one second in real time.
# 
# An SQL Query to provide the title records

#select bib.bid, books.isbn,bib.CALLNUMBER, bib.title
#from SCIENCE_TECH_BOOKS_2025 books
#     inner join bbibmap_v2 bib  on (bib.isbn = books.isbn)
;
#expected csv file columns:   
#$isbn
#
