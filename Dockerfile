FROM perl:5.26

RUN cpanm \
    Term::ReadKey \
    Term::ReadLine \
    Term::ReadLine::Gnu \
    PadWalker \
    HTTP::Request \
    LWP::UserAgent \
    JSON \
    Lingua::Translit \
    DBI \
    DBD::Pg \
    DBIx::Placeholder::Named \
    LWP::Protocol::https \
    DateTime \
    DateTime::Format::MySQL \
    DDP \
    HTML::TreeBuilder::XPath \
    LWP::ConsoleLogger::Everywhere \
    LWP::ConsoleLogger::Easy

ADD ./collect.pl ./Dockerfile ./Makefile ./tool_event_details.pl /root/collector/
ADD ./lib /root/collector/lib

CMD while true; do perl ./collector/collect.pl --cache-duration=0.9; sleep 3600; done
