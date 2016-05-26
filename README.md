## Import iTunes into Elasticsearch (Ruby)

Usage:

```
# install elasticsearch via brew, etc
brew install elasticsearch

# check out git project
git clone git@github.com:EricLondon/ruby-import-itunes-elasticsearch.git
cd ruby-import-itunes-elasticsearch

# install gems
bundle install

# copy iTunes library XML into project space
cp ~/Music/iTunes/iTunes\ Music\ Library.xml .

# create index mapping
./elasticsearch.rb --create-mapping

# import data
./elasticsearch.rb --index
```
