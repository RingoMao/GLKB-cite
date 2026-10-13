import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GLKBCiteCore

final class PubMedArticleTests: XCTestCase {
    private static let suiteGate = DispatchSemaphore(value: 1)

    override func setUp() {
        super.setUp()
        Self.suiteGate.wait()
        URLProtocolFixture.reset()
    }

    override func tearDown() {
        URLProtocolFixture.reset()
        Self.suiteGate.signal()
        super.tearDown()
    }

    // MARK: Parser

    func testParserReadsEveryCitationFieldFromRecordedEfetchXML() throws {
        let articles = try PubMedArticleParser.parse(TestFixtures.data(named: "pubmed-efetch", extension: "xml"))
        XCTAssertEqual(articles.map(\.pmid), ["8028670", "38291045", "37012298"])

        let nature = articles[0]
        XCTAssertEqual(nature.title, "p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes.")
        XCTAssertEqual(nature.journalTitle, "Nature")
        XCTAssertEqual(nature.journalAbbreviation, "Nature")
        XCTAssertEqual(nature.volume, "370")
        XCTAssertEqual(nature.issue, "6486")
        XCTAssertEqual(nature.year, "1994")
        XCTAssertEqual(nature.month, "Jul")
        XCTAssertEqual(nature.day, "21")
        XCTAssertEqual(nature.pages, "220-3")
        XCTAssertEqual(nature.doi, "10.1038/370220a0")
        XCTAssertEqual(nature.authors.count, 3)
        XCTAssertEqual(nature.authors.first, ArticleAuthor(lastName: "Caelles", foreName: "C", initials: "C"))

        let sciRep = articles[1]
        XCTAssertEqual(sciRep.journalTitle, "Scientific reports")
        XCTAssertEqual(sciRep.journalAbbreviation, "Sci Rep")
        XCTAssertEqual(sciRep.volume, "14")
        XCTAssertEqual(sciRep.issue, "1")
        XCTAssertEqual(sciRep.pages, "2461")
        XCTAssertEqual(sciRep.doi, "10.1038/s41598-024-51292-4")
        XCTAssertEqual(sciRep.authors.first, ArticleAuthor(lastName: "Zhang", foreName: "Mengdi", initials: "M"))
        XCTAssertEqual(sciRep.year, "2024")
        XCTAssertEqual(sciRep.month, "Jan")
    }

    func testParserHandlesMarkupInTitlesMedlineDatesAndGroupAuthors() throws {
        let xml = """
        <?xml version="1.0"?>
        <PubmedArticleSet>
          <PubmedArticle>
            <MedlineCitation Status="MEDLINE" Owner="NLM">
              <PMID Version="1">0042</PMID>
              <Article PubModel="Print">
                <Journal>
                  <ISOAbbreviation>J Test</ISOAbbreviation>
                  <Title>The journal of testing</Title>
                  <JournalIssue CitedMedium="Print">
                    <Volume>7</Volume>
                    <PubDate><MedlineDate>1999 Jul-Aug</MedlineDate></PubDate>
                  </JournalIssue>
                </Journal>
                <ArticleTitle>Effects of <i>BRCA1</i> &amp; TGF-&#x03B2; on H<sub>2</sub>O.</ArticleTitle>
                <Pagination><MedlinePgn>12-9; discussion 20-1</MedlinePgn></Pagination>
                <ELocationID EIdType="doi" ValidYN="Y">10.1000/eloc</ELocationID>
                <AuthorList CompleteYN="Y">
                  <Author ValidYN="Y"><CollectiveName>GBD 2019 Collaborators</CollectiveName></Author>
                  <Author ValidYN="Y"><LastName>Smith</LastName><ForeName>John Robert</ForeName><Initials>JR</Initials><Suffix>Jr</Suffix></Author>
                  <Author ValidYN="N"><LastName>Wrong</LastName><ForeName>W</ForeName><Initials>W</Initials></Author>
                  <Author ValidYN="Y"><Initials>X</Initials></Author>
                </AuthorList>
              </Article>
              <CommentsCorrectionsList>
                <CommentsCorrections RefType="Cites"><RefSource>Other</RefSource><PMID Version="1">999999</PMID></CommentsCorrections>
              </CommentsCorrectionsList>
            </MedlineCitation>
            <PubmedData>
              <ArticleIdList>
                <ArticleId IdType="pubmed">42</ArticleId>
                <ArticleId IdType="doi">10.1000/authoritative</ArticleId>
              </ArticleIdList>
              <ReferenceList>
                <Reference>
                  <Citation>A cited work</Citation>
                  <ArticleIdList><ArticleId IdType="doi">10.9999/cited-work</ArticleId></ArticleIdList>
                </Reference>
              </ReferenceList>
            </PubmedData>
          </PubmedArticle>
        </PubmedArticleSet>
        """
        let articles = try PubMedArticleParser.parse(Data(xml.utf8))
        let article = try XCTUnwrap(articles.first)
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(article.pmid, "42")
        XCTAssertEqual(article.title, "Effects of BRCA1 & TGF-β on H2O.")
        XCTAssertEqual(article.journalTitle, "The journal of testing")
        XCTAssertEqual(article.journalAbbreviation, "J Test")
        XCTAssertEqual(article.year, "1999")
        XCTAssertEqual(article.month, "Jul-Aug")
        XCTAssertNil(article.issue)
        XCTAssertEqual(article.pages, "12-9; discussion 20-1")
        XCTAssertEqual(article.doi, "10.1000/authoritative")
        XCTAssertEqual(article.authors, [
            ArticleAuthor(collectiveName: "GBD 2019 Collaborators"),
            ArticleAuthor(lastName: "Smith", foreName: "John Robert", initials: "JR", suffix: "Jr"),
        ])
    }

    func testParserReadsBookshelfChaptersSeasonsLocatorsAndPublicationTypes() throws {
        let xml = """
        <?xml version="1.0"?>
        <PubmedArticleSet>
          <PubmedBookArticle>
            <BookDocument>
              <PMID Version="1">42862929</PMID>
              <ArticleIdList><ArticleId IdType="bookaccession">NBK625318</ArticleId></ArticleIdList>
              <Book>
                <Publisher>
                  <PublisherName>University of Washington, Seattle</PublisherName>
                  <PublisherLocation>Seattle (WA)</PublisherLocation>
                </Publisher>
                <BookTitle book="gene">GeneReviews<sup>&#xAE;</sup></BookTitle>
                <PubDate><Year>1993</Year></PubDate>
                <AuthorList Type="editors"><Author ValidYN="Y"><LastName>Adam</LastName><ForeName>Margaret P</ForeName><Initials>MP</Initials></Author></AuthorList>
                <AuthorList Type="authors"><Author ValidYN="Y"><LastName>Bookwide</LastName><ForeName>Author</ForeName><Initials>A</Initials></Author></AuthorList>
                <Medium>Internet</Medium>
              </Book>
              <ArticleTitle book="gene" part="cerd">Ceramide Transporter Syndrome</ArticleTitle>
              <AuthorList Type="authors"><Author ValidYN="Y"><LastName>Regan-Fendt</LastName><ForeName>Kelly</ForeName><Initials>K</Initials></Author></AuthorList>
              <PublicationType UI="D016454">Review</PublicationType>
              <ContributionDate><Year>2026</Year><Month>10</Month><Day>8</Day></ContributionDate>
              <ReferenceList><Reference><Citation>Cited work</Citation><ArticleIdList><ArticleId IdType="doi">10.9999/cited</ArticleId></ArticleIdList></Reference></ReferenceList>
            </BookDocument>
            <PubmedBookData><ArticleIdList><ArticleId IdType="pubmed">42862929</ArticleId></ArticleIdList></PubmedBookData>
          </PubmedBookArticle>
          <PubmedArticle>
            <MedlineCitation Status="MEDLINE"><PMID Version="1">38206862</PMID>
              <Article>
                <Journal><ISOAbbreviation>Elife</ISOAbbreviation><Title>eLife</Title>
                  <JournalIssue><Volume>12</Volume><PubDate><Year>1965</Year><Season>Nov-Dec</Season></PubDate></JournalIssue></Journal>
                <ArticleTitle>Frogs.</ArticleTitle>
                <ELocationID EIdType="pii" ValidYN="Y">e85096</ELocationID>
                <ELocationID EIdType="doi" ValidYN="Y">10.7554/eLife.85096</ELocationID>
                <AuthorList><Author ValidYN="Y"><LastName>Jr</LastName><ForeName>Fedor Čiampor</ForeName><Initials>FČ</Initials></Author></AuthorList>
                <PublicationTypeList><PublicationType>Journal Article</PublicationType><PublicationType>Retracted Publication</PublicationType></PublicationTypeList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
          <PubmedArticle>
            <MedlineCitation Status="PubMed-not-MEDLINE"><PMID Version="1">42859506</PMID>
              <Article>
                <Journal><ISOAbbreviation>ArXiv</ISOAbbreviation><Title>ArXiv</Title><JournalIssue><PubDate><Year>2026</Year><Month>Oct</Month><Day>02</Day></PubDate></JournalIssue></Journal>
                <ArticleTitle>Autoencoders.</ArticleTitle>
                <ELocationID EIdType="pii" ValidYN="Y">arXiv:2610.03640v1</ELocationID>
                <ELocationID EIdType="pii" ValidYN="Y">d6ra03309a</ELocationID>
                <PublicationTypeList><PublicationType>Preprint</PublicationType></PublicationTypeList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
        </PubmedArticleSet>
        """
        let articles = try PubMedArticleParser.parse(Data(xml.utf8))
        XCTAssertEqual(articles.map(\.pmid), ["42862929", "38206862", "42859506"])

        let chapter = articles[0]
        XCTAssertEqual(chapter.kind, .bookChapter)
        XCTAssertEqual(chapter.title, "Ceramide Transporter Syndrome")
        XCTAssertEqual(chapter.bookTitle, "GeneReviews\u{AE}")
        XCTAssertEqual(chapter.publisher, "University of Washington, Seattle")
        XCTAssertEqual(chapter.publisherLocation, "Seattle (WA)")
        XCTAssertEqual(chapter.year, "1993")
        XCTAssertEqual(chapter.bookshelfID, "NBK625318")
        XCTAssertEqual(chapter.bookshelfURL?.absoluteString, "https://www.ncbi.nlm.nih.gov/books/NBK625318/")
        XCTAssertEqual(chapter.authors, [ArticleAuthor(lastName: "Regan-Fendt", foreName: "Kelly", initials: "K")],
                       "chapter authors win over the book's authors")
        XCTAssertEqual(chapter.editors, [ArticleAuthor(lastName: "Adam", foreName: "Margaret P", initials: "MP")])
        XCTAssertEqual(chapter.publicationTypes, ["Review"])
        XCTAssertEqual(chapter.contributionDate, ArticleDate(year: "2026", month: "10", day: "8"))
        XCTAssertNil(chapter.doi, "a cited work's DOI is not the chapter's")

        let elife = articles[1]
        XCTAssertEqual(elife.month, "Nov-Dec")
        XCTAssertEqual(elife.articleNumber, "e85096")
        XCTAssertEqual(elife.doi, "10.7554/eLife.85096")
        XCTAssertTrue(elife.isRetracted)
        XCTAssertFalse(elife.isPreprint)

        let preprint = articles[2]
        XCTAssertEqual(preprint.articleNumber, "arXiv:2610.03640v1", "a publisher's internal pii is not an article number")
        XCTAssertTrue(preprint.isPreprint)
        XCTAssertFalse(preprint.isRetracted)
        XCTAssertNil(preprint.bookshelfURL)
    }

    func testArticleNumberRecognition() {
        XCTAssertTrue(PubMedArticleParser.isArticleNumber("e85096"))
        XCTAssertTrue(PubMedArticleParser.isArticleNumber("E0261090"))
        XCTAssertTrue(PubMedArticleParser.isArticleNumber("arXiv:2610.03640v1"))
        XCTAssertTrue(PubMedArticleParser.isArticleNumber("2461"))
        XCTAssertFalse(PubMedArticleParser.isArticleNumber("d6ra03309a"))
        XCTAssertFalse(PubMedArticleParser.isArticleNumber("10.1177_09727531261479841"))
        XCTAssertFalse(PubMedArticleParser.isArticleNumber("S0140-6736(20)30925-9"))
        XCTAssertFalse(PubMedArticleParser.isArticleNumber("12"))
    }

    func testParserRejectsNonXMLAndForeignXML() {
        XCTAssertThrowsError(try PubMedArticleParser.parse(Data("<html><body>captive portal</body></html>".utf8)))
        XCTAssertThrowsError(try PubMedArticleParser.parse(Data("{\"status\":\"ok\"}".utf8)))
        XCTAssertEqual(try PubMedArticleParser.parse(Data("<PubmedArticleSet/>".utf8)), [])
    }

    func testMedlineDateSplitsYearFromTheRest() {
        XCTAssertEqual(PubMedArticleParser.medlineDate("1994 Jul-Aug").year, "1994")
        XCTAssertEqual(PubMedArticleParser.medlineDate("1994 Jul-Aug").month, "Jul-Aug")
        XCTAssertEqual(PubMedArticleParser.medlineDate("2000 Spring").month, "Spring")
        XCTAssertEqual(PubMedArticleParser.medlineDate("1998 Dec-1999 Jan").year, "1998")
        XCTAssertNil(PubMedArticleParser.medlineDate("Summer").year)
    }

    // MARK: Service

    func testServiceRequestsCanonicalIdentifiersOnceAndKeysResultsByPMID() async throws {
        let fixture = try TestFixtures.data(named: "pubmed-efetch", extension: "xml")
        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/xml; charset=UTF-8"]
            )!
            return (response, fixture)
        }
        let service = PubMedArticleService(
            endpoint: URL(string: "https://eutils.test/entrez/eutils/efetch.fcgi")!,
            session: URLProtocolFixture.makeSession()
        )
        let articles = try await service.articles(for: ["8028670", "0038291045", "38291045", "not-a-pmid", " 37012298 "])
        XCTAssertEqual(Set(articles.keys), ["8028670", "38291045", "37012298"])
        XCTAssertEqual(articles["38291045"]?.doi, "10.1038/s41598-024-51292-4")

        let request = try XCTUnwrap(URLProtocolFixture.lastRequest())
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.host, "eutils.test")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("db"), "pubmed")
        XCTAssertEqual(value("id"), "8028670,38291045,37012298")
        XCTAssertEqual(value("retmode"), "xml")
        XCTAssertEqual(value("tool"), "glkb-cite")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(URLProtocolFixture.requestCount(), 1)
    }

    func testServiceSkipsTheNetworkWithoutValidIdentifiers() async throws {
        let service = PubMedArticleService(session: URLProtocolFixture.makeSession())
        let articles = try await service.articles(for: ["abc", ""])
        XCTAssertTrue(articles.isEmpty)
        XCTAssertNil(URLProtocolFixture.lastRequest())
    }

    func testServiceRefusesRedirectsAndNonXMLBodies() async {
        let service = PubMedArticleService(
            endpoint: URL(string: "https://eutils.test/entrez/eutils/efetch.fcgi")!,
            session: URLProtocolFixture.makeSession()
        )
        URLProtocolFixture.setHandler { request in
            if request.url?.host == "eutils.test" {
                return (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                        headerFields: ["Location": "https://elsewhere.test/"])!, Data())
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "text/xml"])!, Data("<PubmedArticleSet/>".utf8))
        }
        do {
            _ = try await service.articles(for: ["42"])
            XCTFail("Expected the redirect to be refused")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .requestFailed(statusCode: 302, message: nil))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.requestCount(), 1)

        URLProtocolFixture.setHandler { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                             headerFields: ["Content-Type": "text/html"])!, Data("<html/>".utf8))
        }
        do {
            _ = try await service.articles(for: ["42"])
            XCTFail("Expected malformedResponse")
        } catch let error as LiteratureError {
            guard case .malformedResponse(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("text/html"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
