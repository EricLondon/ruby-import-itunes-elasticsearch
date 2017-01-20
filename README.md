## Import iTunes into Elasticsearch (Ruby)

Usage:

```
# install elasticsearch via brew, etc
brew install elasticsearch
brew services start elasticsearch

# check out git project
git clone git@github.com:EricLondon/ruby-import-itunes-elasticsearch.git
cd ruby-import-itunes-elasticsearch

# install gems
bundle install

# copy iTunes library XML into project space
cp ~/Music/iTunes/iTunes\ Music\ Library.xml ./Library.xml

# create index mapping
./elasticsearch.rb --create-mapping

# import track data
./elasticsearch.rb --index-tracks

# import playlist data
./elasticsearch.rb --index-playlists
```

See [this repo](https://github.com/EricLondon/itunes-nodejs-elasticsearch-front-end) for a NodeJS front-end to facet and search.
