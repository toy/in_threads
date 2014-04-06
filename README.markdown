# in_threads

Easily execute ruby code in parallel.

[![Build Status](https://travis-ci.org/toy/in_threads.png?branch=master)](https://travis-ci.org/toy/in_threads)

## Installation

    gem install in_threads

## Usage

By default there is maximum of 10 simultaneous threads

    urls.in_threads.map do |url|
      url.fetch
    end

    urls.in_threads.each do |url|
      url.save_to_disk
    end

    numbers.in_threads(2).map do |number|
      # whery long and complicated formula
      # using only 2 threads
    end

You can use any Enumerable method, but some of them can not use threads (`inject`, `reduce`) or don't use blocks (`to_a`, `entries`, `drop`, `take`, `first`, `include?`, `member?`) or have both problems depending on usage type (`min`, `max`, `minmax`, `sort`)

    urls.in_threads.any?(&:ok?)
    urls.in_threads.all?(&:ok?)
    urls.in_threads.none?(&:error?)
    urls.in_threads.grep(/example\.com/, &:fetch)

## Copyright

Copyright (c) 2010-2014 Ivan Kuchin. See LICENSE.txt for details.
